#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_BAUD="${DEFAULT_BAUD:-115200}"
STATE_FILE="/tmp/mcdev"

have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
notify() {
  if have dunstify; then
    dunstify "$1" "$2" || true
  else notify-send "$1" "$2" || true; fi
}

pick_serial_port() {
  local p
  for p in /dev/serial/by-id/*; do [ -e "$p" ] && {
    readlink -f "$p"
    return 0
  }; done
  ls -t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n1
}

wait_for_serial() {
  local p
  for _ in {1..50}; do
    p=$(pick_serial_port || true)
    [ -n "${p:-}" ] && {
      echo "$p"
      return 0
    }
    sleep 0.1
  done
  return 1
}

udev_prop() { udevadm info -q property -n "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -n1; }

is_micropython() {
  local port="$1"
  have mpremote || return 1
  local out
  out=$(mpremote --quiet connect "$port" exec "import sys; print(sys.implementation.name)" 2>/dev/null || true)
  [[ "$out" =~ [Mm]icro[Pp]ython ]]
}

is_esp() {
  local port="$1"
  have esptool.py || have esptool || return 1
  local tool="esptool.py"
  have esptool && tool="esptool"
  "$tool" --chip auto --port "$port" --before default_reset --after no_reset chip_id 2>&1 |
    grep -Eq 'Detecting chip type|Chip is|Features:'
}

open_terminal() {
  local port="$1" baud="$2"
  # Launch picocom in a terminal if available; else inline (blocking)
  local cmd="picocom -b $baud --imap lfcrlf --omap crcrlf '$port'"
  if have wezterm; then
    wezterm start -- bash -lc "picocom -b $baud --imap lfcrlf --omap crcrlf '$port'"
  elif have xterm; then
    xterm -T "Serial ($port)" -e bash -lc "$cmd" &
  elif have gnome-terminal; then
    gnome-terminal -- bash -lc "$cmd" &
  elif have konsole; then
    konsole -e bash -lc "$cmd" &
  else
    eval "$cmd"
  fi
}

main() {
  sleep 0.6
  local PORT VID TYPE="UNKNOWN"
  PORT=$(wait_for_serial || true)
  [ -z "${PORT:-}" ] && {
    log "no serial device"
    notify "🔌 No serial device" "Plug a board in."
    exit 0
  }

  # permissions hint (doesn't abort)
  if [ ! -r "$PORT" ] || [ ! -w "$PORT" ]; then
    local grp
    grp=$(stat -c %G "$PORT" 2>/dev/null || echo '?')
    notify "⚠️ No permission for $PORT" "Group: $grp — add your user and re-login."
  fi

  VID=$(udev_prop "$PORT" ID_VENDOR_ID)

  # VID map
  case "${VID,,}" in
  303a) TYPE="ESP" ;;            # Espressif
  2e8a) TYPE="PICO" ;;           # Raspberry Pi (RP2040)
  2341 | 2a03) TYPE="ARDUINO" ;; # Arduino
  esac

  # Probes (lightweight)
  [ "$TYPE" = "UNKNOWN" ] && is_esp "$PORT" && TYPE="ESP"
  [ "$TYPE" = "UNKNOWN" ] && is_micropython "$PORT" && TYPE="MICROPY"
  [ "$TYPE" = "UNKNOWN" ] && TYPE="ARDUINO" # generic USB-serial fallback

  log "detected type=$TYPE port=$PORT vid=${VID:-?}"

  # Persist for mcflash
  {
    echo "PORT=$PORT"
    echo "TYPE=$TYPE"
  } >"$STATE_FILE"

  # Open serial terminal
  open_terminal "$PORT" "$DEFAULT_BAUD"

  # Flash hint
  case "$TYPE" in
  ESP) notify "⚙️ ESP detected" "Use: mcflash firmware.bin" ;;
  PICO) notify "🐣 Pico detected" "Use: mcflash firmware.uf2" ;;
  MICROPY) notify "🐍 MicroPython board" "Use: mcflash your_script.py" ;;
  ARDUINO) notify "🔧 Arduino-like device" "Use: mcflash sketch.hex" ;;
  esac
}

main "$@"
