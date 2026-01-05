#!/usr/bin/env bash
set -Eeuo pipefail

# ===================== simple config =====================
IGNORE_PORTS=${IGNORE_PORTS:-"/dev/ttyACM0"}
# Ignore Fibocom (2cb7) + Nordic nRF DK (1915)
IGNORE_VIDS=${IGNORE_VIDS:-"2cb7 1915"}
DEFAULT_BAUD=${DEFAULT_BAUD:-115200}
STATE_FILE="/tmp/mcdev"
# =========================================================

have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
notify() {
  if have dunstify; then
    dunstify "$1" "$2" || true
  else
    notify-send "$1" "$2" || true
  fi
}

udev_prop() { udevadm info -q property -n "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -n1; }
get_vid() {
  local v
  v=$(udev_prop "$1" ID_VENDOR_ID || true)
  printf "%s" "${v,,}"
}

is_ignored_port() {
  local p="$1"
  for x in $IGNORE_PORTS; do
    [ "$p" = "$x" ] && {
      log "ignore(port): $p"
      return 0
    }
  done
  local vid
  vid="$(get_vid "$p" || true)"
  for v in $IGNORE_VIDS; do
    [ -n "$vid" ] && [ "${vid,,}" = "${v,,}" ] && {
      log "ignore(vid=$vid): $p"
      return 0
    }
  done
  return 1
}

byid_name_for() {
  [ -d /dev/serial/by-id ] || {
    echo ""
    return
  }
  local dev="$1" link
  for link in /dev/serial/by-id/*; do
    [ -e "$link" ] || continue
    [ "$(readlink -f "$link")" = "$dev" ] && {
      basename "$link"
      return
    }
  done
  echo ""
}

pick_serial() {
  if [ -d /dev/serial/by-id ]; then
    for s in /dev/serial/by-id/*; do
      [ -e "$s" ] || continue
      readlink -f "$s"
    done
  fi
  ls -t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true
}

is_micropython() {
  local port="$1"
  have mpremote || return 1
  local out
  out=$(mpremote --quiet connect "port:${port}" exec "import sys; print(sys.implementation.name)" 2>/dev/null ||
    mpremote --quiet exec "import sys; print(sys.implementation.name)" 2>/dev/null || true)
  echo "$out" | grep -qi "micropython"
}

classify() {
  local port="$1" vid="$2" type="UNKNOWN"
  if is_micropython "$port"; then
    echo "MICROPY"
    return 0
  fi
  case "$vid" in
  303a) type="ESP" ;;
  2e8a) type="PICO" ;;
  2341 | 2a03) type="ARDUINO" ;;
  *) type="GENERIC" ;;
  esac
  echo "$type"
}

open_terminal() {
  local port="$1" baud="$2"
  local cmd="picocom -b $baud --imap lfcrlf --omap crcrlf --nolock '$port'"
  if have wezterm; then
    wezterm start -- bash -lc "$cmd"
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
  sleep 0.4

  local PORT=""
  for p in $(pick_serial); do
    [ -e "$p" ] || continue
    if is_ignored_port "$p"; then
      continue
    fi
    PORT="$p"
    break
  done

  if [ -z "$PORT" ]; then
    log "no usable serial device"
    rm -f "$STATE_FILE" # prevent mcflash from using stale info
    exit 0
  fi

  if [ ! -r "$PORT" ] || [ ! -w "$PORT" ]; then
    local grp
    grp=$(stat -c %G "$PORT" 2>/dev/null || echo '?')
    log "no permission on $PORT"
    notify "⚠️ No permission" "$PORT (group $grp)"
    exit 1
  fi

  local VID
  VID="$(get_vid "$PORT" || true)"
  local TYPE
  TYPE="$(classify "$PORT" "$VID")"

  log "selected: port=$PORT vid=${VID:-??} type=$TYPE byid=$(byid_name_for "$PORT")"

  {
    echo "PORT=$PORT"
    echo "TYPE=$TYPE"
  } >"$STATE_FILE"

  case "$TYPE" in
  MICROPY) notify "🐍 MicroPython" "Use: mcflash your_script.py" ;;
  ESP) notify "⚙️ ESP" "Use: mcflash firmware.bin" ;;
  PICO) notify "🐣 Pico" "Use: mcflash firmware.uf2" ;;
  ARDUINO) notify "🔧 Arduino" "Use: mcflash sketch.hex" ;;
  esac

  open_terminal "$PORT" "$DEFAULT_BAUD"
}

main "$@"
