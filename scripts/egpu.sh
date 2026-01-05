#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: egpu <program> [args...]"
  exit 64
fi

# --- tiny notify helper (prefers dunstify) ---
notify() {
  local urgency="${1:-normal}"; shift || true
  local title="${1:-egpu}"; shift || true
  local body="${*:-}"
  if command -v dunstify >/dev/null 2>&1; then
    local icon="dialog-information"
    [[ "$urgency" == "critical" ]] && icon="dialog-error"
    [[ "$urgency" == "low" ]] && urgency="low"
    dunstify -u "$urgency" -i "$icon" "$title" "$body" >/dev/null 2>&1 || true
  else
    printf '%s: %s\n' "$title" "$body" >&2
  fi
}

# --- preflight: detect driver state but NEVER block program start ---
driver_dead=0
have_nvidia_smi=0
if command -v nvidia-smi >/dev/null 2>&1; then
  have_nvidia_smi=1
  if ! out="$(nvidia-smi 2>&1)"; then
    if grep -qiE "couldn'?t communicate with the nvidia driver|failed to initialize nvml" <<<"$out"; then
      driver_dead=1
      notify critical "❌ NVIDIA driver not running!" "Did you boot with NVIDIA?"
      # continue anyway
    fi
  fi
else
  notify low "⚠️ No nvidia-smi" "Cannot verify GPU usage; nvidia-smi not available."
fi

# --- export PRIME offload hints for NVIDIA + GLVND ---
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only

# If on X11 and xrandr is present, associate providers and set the exact NV provider name
if [[ -n "${DISPLAY-}" ]] && command -v xrandr >/dev/null 2>&1; then
  if xrandr --listproviders | grep -q 'NVIDIA'; then
    src=$(xrandr --listproviders | awk -F'name:' '/modesetting/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
    nv=$(xrandr --listproviders | awk -F'name:' '/NVIDIA/{gsub(/^[ \t]+/,"",$2); print $2; exit}')
    if [[ -n "${src}" && -n "${nv}" ]]; then
      xrandr --setprovideroffloadsink "${src}" "${nv}" >/dev/null 2>&1 || true
      export __NV_PRIME_RENDER_OFFLOAD_PROVIDER="${nv}"
    fi
  fi
fi

prog="$1"

# Firefox quirks: on Xorg, force X/GLX; on Wayland sessions, allow Wayland
if [[ "${prog}" = "firefox" || "${prog}" = "firefox-bin" ]]; then
  case "${XDG_SESSION_TYPE-}" in
    x11|"") export MOZ_ENABLE_WAYLAND=0 ;;
    wayland) export MOZ_ENABLE_WAYLAND=1 ;;
  esac
  export MOZ_WEBRENDER=1
fi

# Keep GPU from deep-idle so nvidia-smi shows activity (ignore failure)
if [[ $have_nvidia_smi -eq 1 ]]; then
  nvidia-smi -pm 1 >/dev/null 2>&1 || true
fi

# --- launch program (not exec) so we can observe PID, then wait and forward exit code ---
"$@" &
pid=$!

# --- detector: verify the PID actually hits the NVIDIA GPU ---
detect_seconds="${EGPU_CHECK_SECONDS:-8}"       # total window
detect_interval="${EGPU_CHECK_INTERVAL:-0.5}"   # polling step

uses_nvidia_pid() {
  local target_pid="$1"
  if [[ $have_nvidia_smi -eq 1 ]]; then
    if nvidia-smi pmon -c 1 >/dev/null 2>&1; then
      nvidia-smi pmon -c 1 2>/dev/null | awk 'NR>2 {print $2}' | grep -qx "$target_pid" && return 0
    fi
    if nvidia-smi >/dev/null 2>&1; then
      nvidia-smi 2>/dev/null | grep -E " ${target_pid} " >/dev/null 2>&1 && return 0
    fi
  fi
  return 1
}

# If driver is dead, don't bother polling; just warn once and move on.
if [[ $driver_dead -eq 0 ]]; then
  (
    sleep "$detect_interval"
    t=0
    seen=0
    while kill -0 "$pid" >/dev/null 2>&1 && (( $(echo "$t < $detect_seconds" | bc -l) )); do
      if uses_nvidia_pid "$pid"; then
        seen=1
        break
      fi
      sleep "$detect_interval"
      t=$(echo "$t + $detect_interval" | bc)
    done

    if [[ $seen -eq 1 ]]; then
      notify normal "✅ eGPU active!" "✅ $prog is running on NVIDIA"
    else
      notify normal "✅ eGPU active!" "⚠️ $prog didn’t show on NVIDIA"
    fi
  ) & disown
fi

# Wait for program and forward its exit status
wait "$pid"
exit $?
