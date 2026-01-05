#!/usr/bin/env bash
# mcflash — flash *.bin/*.uf2/*.hex or push *.py (as /main.py),
# then force-start the MCU and restart your auto-connect script.
# Usage: mcflash <firmware.{bin|uf2|hex|py}> [extra-args]

set -Eeuo pipefail

STATE_FILE="${STATE_FILE:-/tmp/mcdev}"
MPY_AUTORUN_AFTER_RECONNECT="${MPY_AUTORUN_AFTER_RECONNECT:-1}"

# --- keep these in sync with your connect script ---
IGNORE_PORTS=${IGNORE_PORTS:-"/dev/ttyACM0"}
IGNORE_VIDS=${IGNORE_VIDS:-"2cb7"} # Fibocom default
DEFAULT_BAUD=${DEFAULT_BAUD:-115200}

die() {
  printf "mcflash: %s\n" "$*" >&2
  exit 1
}
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

udev_prop() { udevadm info -q property -n "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -n1; }
get_vid() { printf "%s" "$(udev_prop "$1" ID_VENDOR_ID 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"; }

is_ignored_port() {
  local p="$1" vid
  for x in $IGNORE_PORTS; do [[ "$p" == "$x" ]] && {
    log "ignore(port): $p"
    return 0
  }; done
  vid="$(get_vid "$p" || true)"
  for v in $IGNORE_VIDS; do
    [[ -n "$vid" && "$vid" == "${v,,}" ]] && {
      log "ignore(vid=$vid): $p"
      return 0
    }
  done
  return 1
}

port_rw_ok() { [[ -r "$1" && -w "$1" ]]; }

close_users_of_port() {
  local port="$1" killed=0
  if have fuser; then fuser -k "$port" 2>/dev/null && killed=1 || true; fi
  if have lsof; then
    local pids
    pids="$(lsof -t "$port" 2>/dev/null || true)"
    [[ -n "$pids" ]] && {
      kill $pids 2>/dev/null || true
      killed=1
    }
  fi
  [[ $killed -eq 1 ]] && sleep 0.6
}

wait_until_free() {
  local port="$1" tries="${2:-30}"
  for _ in $(seq 1 "$tries"); do
    if ! lsof "$port" &>/dev/null && ! fuser "$port" &>/dev/null; then return 0; fi
    sleep 0.2
  done
  return 1
}

# Prefer stable /dev/serial/by-id symlinks when possible
wait_replug() {
  # $1 old devnode, $2 timeout(s, default 20), $3 grep regex for by-id preference
  local old="$1" t_end=$((SECONDS + ${2:-20})) prefer="${3:-.}"
  while [[ -e "$old" && SECONDS -lt $t_end ]]; do sleep 0.2; done
  while ((SECONDS < t_end)); do
    local byid
    byid="$(ls -1t /dev/serial/by-id/ 2>/dev/null | grep -E "$prefer" | head -n1 || true)"
    if [[ -n "$byid" && -e "/dev/serial/by-id/$byid" ]]; then
      readlink -f "/dev/serial/by-id/$byid"
      return 0
    fi
    local n
    n="$(ls -1t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n1 || true)"
    [[ -n "$n" ]] && {
      echo "$n"
      return 0
    }
    sleep 0.2
  done
  return 1
}

# ---- REQUIRED: explicit error handling for the auto-connect script ----
restart_repl() {
  local newport="${1:-}"
  local script=""
  if command -v microcontroller-connect.sh >/dev/null 2>&1; then
    script="$(command -v microcontroller-connect.sh)"
  elif [[ -x "$HOME/GNOM/scripts/microcontroller-connect.sh" ]]; then
    script="$HOME/GNOM/scripts/microcontroller-connect.sh"
  else
    die "microcontroller-connect.sh not found (checked PATH and ~/GNOM/scripts/)"
  fi

  log "[post] launching $script ${newport:+--port $newport}"
  if [[ -n "$newport" ]]; then
    nohup "$script" --port "$newport" >/dev/null 2>&1 &
    disown || die "failed to start auto-connect script"
  else
    nohup "$script" >/dev/null 2>&1 &
    disown || die "failed to start auto-connect script"
  fi
}

# ---- MicroPython helpers ----
mpy_push() {
  # Copy local file to /main.py and verify, then soft-reset so it starts.
  local port="$1" file="$2"
  have mpremote || die "mpremote not installed"

  # Free FS (best-effort) *before* copy; we still reset after to run main.py
  mpremote connect "port:${port}" rawrepl "exec(\"import machine; machine.soft_reset()\")" >/dev/null 2>&1 || true

  local remote=":/main.py" # always autostart name
  if mpremote --help | grep -qE ' cp '; then
    mpremote connect "port:${port}" cp "$file" "$remote" ||
      {
        sleep 1
        mpremote connect "port:${port}" cp "$file" "$remote"
      }
  else
    mpremote connect "port:${port}" fs cp "$file" "$remote" ||
      {
        sleep 1
        mpremote connect "port:${port}" fs cp "$file" "$remote"
      }
  fi

  mpremote connect "port:${port}" exec "import os; os.stat('/main.py')" >/dev/null 2>&1 ||
    die "mpremote copy verification failed (missing /main.py)"

  log "[MPY] soft-reset to start /main.py"
  mpremote connect "port:${port}" soft-reset >/dev/null 2>&1 || true
}

mpy_force_start() {
  # Force the MCU to (re)start /main.py on a given TTY (even if 5V never dropped).
  local port="$1"
  [[ "${MPY_AUTORUN_AFTER_RECONNECT}" == "1" ]] || return 0
  [[ -e "$port" ]] || {
    log "[MPY] port gone: $port"
    return 0
  }

  # Try with mpremote first (hard → soft)
  if have mpremote; then
    log "[MPY] reset via mpremote (hard)"
    if mpremote connect "port:${port}" reset >/dev/null 2>&1; then
      return 0
    fi
    log "[MPY] hard reset failed; trying soft-reset"
    if mpremote connect "port:${port}" soft-reset >/dev/null 2>&1; then
      return 0
    fi
    log "[MPY] mpremote reset paths failed; falling back to raw TTY"
  fi

  # Raw TTY fallback: ^C^C → machine.reset() → ^D
  if have python3; then
    python3 - "$port" <<'PY' 2>/dev/null || true
import os, sys, time, termios
port = sys.argv[1]
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
# raw 115200 8N1
attrs = termios.tcgetattr(fd)
attrs[0] = 0; attrs[1] = 0
attrs[2] = termios.B115200 | termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
termios.tcsetattr(fd, termios.TCSANOW, attrs)

def w(b): os.write(fd, b)

try:
    w(b'\x03\x03')                        # ^C^C break to REPL
    time.sleep(0.15)
    w(b"import machine\r\nmachine.reset()\r\n")  # hard reset
    time.sleep(0.3)
    w(b'\x04')                            # ^D soft reboot (runs boot.py/main.py)
finally:
    os.close(fd)
PY
    log "[MPY] raw reset sequence sent on $port"
    return 0
  fi

  # Minimal fallback without python3
  if have stty; then
    log "[MPY] minimal reset via stty/printf"
    stty -F "$port" raw -echo 115200 || true
    printf '\003\003' >"$port" 2>/dev/null || true # ^C^C
    printf 'import machine\r\nmachine.reset()\r\n' >"$port" 2>/dev/null || true
    printf '\004' >"$port" 2>/dev/null || true # ^D
  fi
}

# =================== args & state ===================
[[ $# -ge 1 ]] || die "usage: mcflash <firmware.{bin|uf2|hex|py}> [extra-args]"
FILE="$1"
shift || true
[[ -f "$FILE" ]] || die "file not found: $FILE"

PORT="${PORT:-}"
TYPE="${TYPE:-}"
if [[ -z "${PORT}" || -z "${TYPE}" ]]; then
  [[ -f "$STATE_FILE" ]] || die "no device info; run microcontroller-connect.sh first"
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi
[[ -n "${PORT:-}" ]] || die "no PORT found (env or $STATE_FILE)"
[[ -n "${TYPE:-}" ]] || die "no TYPE found (env or $STATE_FILE)"
[[ -e "$PORT" ]] || die "port not present: $PORT"
is_ignored_port "$PORT" && die "refusing to flash ignored device: $PORT"
port_rw_ok "$PORT" || die "no permission on $PORT (need rw)"

EXT="${FILE##*.}"
EXT="${EXT,,}"

# Free the line before flashing/copying
close_users_of_port "$PORT"
wait_until_free "$PORT" || die "port is still busy: $PORT"

# =================== per-format actions ===================
NEWPORT=""
case "$EXT" in
bin) # ESP32/ESP8266
  tool="esptool.py"
  have esptool && tool="esptool"
  have "$tool" || die "esptool not installed"
  OFFSET="${ESP_OFFSET:-0x10000}"
  log "[ESP] tool=$tool port=$PORT offset=$OFFSET file=$FILE"
  "$tool" --chip auto -p "$PORT" --before default_reset --after hard_reset \
    write_flash "$OFFSET" "$FILE" "$@"
  NEWPORT="$(wait_replug "$PORT" "${ESP_REPLUG_TIMEOUT:-20}" "${ESP_BYID_REGEX:-ESP|Silicon_Labs|CP210|CH340}" || true)"
  ;;

uf2) # Raspberry Pi Pico (RP2040) via picotool
  have picotool || die "picotool not installed"
  log "[PICO] rebooting to BOOTSEL (ignore if already there)"
  picotool reboot -f || true
  log "[PICO] loading UF2: $FILE"
  picotool load -v -x "$FILE"
  log "[PICO] rebooting app"
  picotool reboot || true
  NEWPORT="$(wait_replug "$PORT" "${PICO_REPLUG_TIMEOUT:-20}" "${PICO_BYID_REGEX:-Pico|RP2040}" || true)"
  ;;

hex) # Arduino AVR
  have avrdude || die "avrdude not installed"
  AVR_MCU="${AVR_MCU:-atmega328p}"
  AVR_BAUD="${AVR_BAUD:-115200}"  # set 57600 for some old Nanos
  AVR_PROG="${AVR_PROG:-arduino}" # or arduino_ft232r, stk500, etc.
  log "[AVR] mcu=$AVR_MCU prog=$AVR_PROG baud=$AVR_BAUD port=$PORT"
  avrdude -p "$AVR_MCU" -c "$AVR_PROG" -P "$PORT" -b "$AVR_BAUD" -D -U "flash:w:$FILE:i"
  NEWPORT="$(wait_replug "$PORT" "${AVR_REPLUG_TIMEOUT:-12}" "${AVR_BYID_REGEX:-Arduino|FTDI|CH340|CP210}" || true)"
  ;;

py) # MicroPython push → /main.py
  log "[MPY] copying to /main.py (autostart)"
  mpy_push "$PORT" "$FILE"
  # MPY typically keeps same node; no forced replug wait.
  ;;

*) die "unknown file type: .$EXT (supported: .bin .uf2 .hex .py)" ;;
esac

# =================== post: force-start + auto-connect ===================
POSTPORT="$PORT"
if [[ -n "${NEWPORT:-}" && -e "$NEWPORT" ]]; then
  POSTPORT="$NEWPORT"
fi

# Kick MicroPython hard/soft so /main.py runs (safe no-op on non-MPY)
mpy_force_start "$POSTPORT"

# Then bring up your terminal/auto-connect on the right port
log "[post] starting connector on $POSTPORT"
restart_repl "$POSTPORT"

echo "[ok] done."
