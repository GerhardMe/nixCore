#!/usr/bin/env bash
# performance.sh — flip performance knobs when entering/leaving "performance" mode
# Usage: performance.sh enable|disable [--aggressive]

# ---- NEVER FAIL BOILERPLATE -----------------------------------------------
# Don't abort on errors, unset vars, or pipeline failures
set +e
set +u
set +o pipefail 2>/dev/null || true
# Swallow any command errors
trap ':' ERR
# ---------------------------------------------------------------------------

ACTION="${1:-}"
AGGRESSIVE="${2:-}"

# --- tiny logger ---
RED=$'\033[91m'; YELLOW=$'\033[93m'; GREEN=$'\033[92m'; RESET=$'\033[0m'
info() { printf '%s\n' "$*"; }
warn() { printf "${YELLOW}⚠ %s${RESET}\n" "$*" >&2; }
err()  { printf "${RED}ERROR:${RESET} %s\n" "$*" >&2; }  # kept for messages only

have() { command -v "$1" >/dev/null 2>&1; }
asroot() {
  if have sudo; then
    sudo -n "$@" >/dev/null 2>&1 || sudo "$@" >/dev/null 2>&1 || "$@" >/dev/null 2>&1 || true
  else
    "$@" >/dev/null 2>&1 || true
  fi
}

SUMMARY=()
addsum() { SUMMARY+=("$1"); }

run() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then info "OK: $desc"; return 0
  else warn "Failed: $desc"; return 1; fi
}
sysfs_write() {
  local path="$1" val="$2" desc="$3"
  [[ -e "$path" ]] || { warn "Missing: $desc ($path)"; return 1; }
  if echo "$val" | asroot tee "$path" >/dev/null 2>&1; then info "OK: $desc"; return 0
  else warn "Failed: $desc ($path)"; return 1; fi
}

# --- CPU ---
choose_governor() {
  local govs_file="$1/scaling_available_governors"
  if [[ -r "$govs_file" ]]; then
    local avail; avail="$(<"$govs_file")"
    for g in schedutil powersave conservative ondemand; do
      [[ " $avail " == *" $g "* ]] && { printf '%s' "$g"; return 0; }
    done
    set -- $avail; printf '%s' "$1"
  else printf '%s' powersave; fi
}

enable_cpu() {
  if have powerprofilesctl; then run "power profile → performance" powerprofilesctl set performance || true; fi
  local ch=0 tot=0
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [[ -e "$p/scaling_governor" ]] || continue
    tot=$((tot+1))
    echo performance | asroot tee "$p/scaling_governor" >/dev/null 2>&1 && { info "OK: ${p##*/} → performance"; ch=$((ch+1)); } || warn "Failed: ${p##*/}"
  done
  addsum "CPU governor: performance (${ch}/${tot})"
  sysfs_write /sys/devices/system/cpu/intel_pstate/no_turbo 0 "Intel Turbo → enabled" || true
  if have sysctl; then asroot sysctl -q vm.swappiness=10 >/dev/null 2>&1 && info "OK: vm.swappiness → 10"; fi
}

disable_cpu() {
  if have powerprofilesctl; then powerprofilesctl set balanced >/dev/null 2>&1 || true; fi
  local ch=0 tot=0
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [[ -e "$p/scaling_governor" ]] || continue
    tot=$((tot+1)); tgt="$(choose_governor "$p")"
    echo "$tgt" | asroot tee "$p/scaling_governor" >/dev/null 2>&1 && { info "OK: ${p##*/} → $tgt"; ch=$((ch+1)); } || warn "Failed: ${p##*/}"
  done
  addsum "CPU governor: reverted (${ch}/${tot})"
  echo 1 | asroot tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null 2>&1 || true
  if have sysctl; then asroot sysctl -q vm.swappiness=60 >/dev/null 2>&1 || true; fi
}

# --- X PRIME offload link (helpful for eGPU) ---
link_offload() {
  [[ -n "${DISPLAY-}" ]] || return 0
  have xrandr || return 0
  local src nv
  src="$(xrandr --listproviders 2>/dev/null | awk -F'name:' '/modesetting/{gsub(/^[ \t]+/,"",$2); print $2; exit}')"
  nv="$(xrandr --listproviders 2>/dev/null | awk -F'name:' '/NVIDIA/{gsub(/^[ \t]+/,"",$2); print $2; exit}')"
  if [[ -n "${src}" && -n "${nv}" ]]; then
    xrandr --setprovideroffloadsink "${src}" "${nv}" >/dev/null 2>&1 && info "OK: PRIME offload link ${src} → ${nv}" || warn "Failed: PRIME offload link"
  fi
}

# --- NVIDIA knobs (safe for PRIME/eGPU) ---
enable_nvidia() {
  have nvidia-smi || { addsum "NVIDIA: not present"; return 0; }

  run "NVIDIA persistence mode ON"  asroot nvidia-smi -pm 1 || true

  if [[ -n "${DISPLAY-}" ]] && have nvidia-settings; then
    nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=1' >/dev/null 2>&1 && info "OK: PowerMizer → Prefer Maximum Performance" || warn "PowerMizer tweak failed"
  fi

  if [[ "$AGGRESSIVE" == "--aggressive" ]]; then
    asroot nvidia-smi -acp UNRESTRICTED >/dev/null 2>&1 || true
    asroot nvidia-smi -rgc >/dev/null 2>&1 || true
    if PL_MAX="$(nvidia-smi -q -d POWER 2>/dev/null | awk -F': ' '/Max Power Limit/{print $2; exit}')"; then
      asroot nvidia-smi -pl "${PL_MAX% W}" >/dev/null 2>&1 && info "OK: Power limit → $PL_MAX" || true
    fi
    addsum "NVIDIA: aggressive perf (if supported)"
  else
    addsum "NVIDIA: persistence + perfmizer"
  fi
}

disable_nvidia() {
  have nvidia-smi || return 0
  if [[ -n "${DISPLAY-}" ]] && have nvidia-settings; then
    nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=0' >/dev/null 2>&1 || true
  fi
  asroot nvidia-smi -rac >/dev/null 2>&1 || true
  asroot nvidia-smi -pm 0  >/dev/null 2>&1 || true
  info "OK: NVIDIA reset; persistence OFF"
  addsum "NVIDIA: reset"
}

# --- I/O schedulers ---
enable_io() {
  local nv_cnt=0 nv_tot=0 sd_cnt=0 sd_tot=0
  for s in /sys/block/nvme*/queue/scheduler; do
    [[ -e "$s" ]] || continue
    nv_tot=$((nv_tot+1)); echo none | asroot tee "$s" >/dev/null 2>&1 && { info "OK: ${s%/queue/*} → none"; nv_cnt=$((nv_cnt+1)); } || warn "Failed: ${s%/queue/*}"
  done
  for s in /sys/block/sd*/queue/scheduler; do
    [[ -e "$s" ]] || continue
    sd_tot=$((sd_tot+1)); grep -q 'mq-deadline' "$s" && echo mq-deadline | asroot tee "$s" >/dev/null 2>&1 && { info "OK: ${s%/queue/*} → mq-deadline"; sd_cnt=$((sd_cnt+1)); } || true
  done
  (( nv_tot>0 )) && addsum "NVMe sched: none (${nv_cnt}/${nv_tot})"
  (( sd_tot>0 )) && addsum "SATA sched: mq-deadline (${sd_cnt}/${sd_tot})"
}
disable_io() {
  local nv_cnt=0 nv_tot=0
  for s in /sys/block/nvme*/queue/scheduler; do
    [[ -e "$s" ]] || continue
    nv_tot=$((nv_tot+1)); echo none | asroot tee "$s" >/dev/null 2>&1 && { info "OK: ${s%/queue/*} → none"; nv_cnt=$((nv_cnt+1)); } || warn "Failed: ${s%/queue/*}"
  done
  (( nv_tot>0 )) && addsum "NVMe sched: none (${nv_cnt}/${nv_tot})"
}

# --- conflicting daemons ---
enable_misc() {
  local stopped=()
  if have systemctl; then
    systemctl is-active --quiet tlp.service                   && { run "stop tlp" asroot systemctl stop tlp.service || true; stopped+=("tlp"); }
    systemctl is-active --quiet power-profiles-daemon.service && { run "stop power-profiles-daemon" asroot systemctl stop power-profiles-daemon.service || true; stopped+=("power-profiles-daemon"); }
    systemctl is-active --quiet auto-cpufreq.service          && { run "stop auto-cpufreq" asroot systemctl stop auto-cpufreq.service || true; stopped+=("auto-cpufreq"); }
  fi
  (( ${#stopped[@]} )) && addsum "Power daemons: stopped (${stopped[*]})" || addsum "Power daemons: none running"
}
disable_misc() {
  local started=()
  if have systemctl; then
    asroot systemctl start power-profiles-daemon.service >/dev/null 2>&1 && started+=("power-profiles-daemon") || true
    asroot systemctl start tlp.service >/dev/null 2>&1 && started+=("tlp") || true
  fi
  (( ${#started[@]} )) && addsum "Power daemons: started (${started[*]})" || addsum "Power daemons: none started"
}

# --- dispatcher (no hard failure on bad args) ---
case "$ACTION" in
  enable)
    info "Enabling performance knobs…"
    enable_misc
    enable_cpu
    link_offload
    enable_nvidia
    enable_io
    echo; echo "Performance features activated:"; printf '  - %s\n' "${SUMMARY[@]}"; echo
    ;;
  disable)
    info "Disabling performance knobs…"
    disable_io
    disable_nvidia
    disable_cpu
    disable_misc
    echo; echo "Performance features deactivated:"; printf '  - %s\n' "${SUMMARY[@]}"; echo
    ;;
  *)
    warn "usage: $0 {enable|disable} [--aggressive]"
    info "No-op; exiting successfully."
    ;;
esac

# Force a successful exit no matter what
exit 0
