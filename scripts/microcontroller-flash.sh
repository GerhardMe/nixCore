#!/usr/bin/env bash
set -Eeuo pipefail

STATE_FILE="/tmp/mcdev"

die() {
    printf "mcflash: %s\n" "$*" >&2
    exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

[ $# -ge 1 ] || die "usage: mcflash <firmware.{bin|uf2|hex|py}> [extra-args]"
FILE="$1"
shift || true
[ -f "$FILE" ] || die "file not found: $FILE"

[ -f "$STATE_FILE" ] || die "no device info; run microcontroller-connect.sh first"
# shellcheck disable=SC1090
source "$STATE_FILE"
[ -n "${PORT:-}" ] || die "no PORT in $STATE_FILE"
[ -n "${TYPE:-}" ] || die "no TYPE in $STATE_FILE"

EXT="${FILE##*.}"
EXT="${EXT,,}"

case "$EXT" in
bin) # ESP
    tool="esptool.py"
    have esptool && tool="esptool"
    have "$tool" || die "esptool not installed"
    OFFSET="${ESP_OFFSET:-0x10000}"
    echo "[ESP] port=$PORT offset=$OFFSET file=$FILE"
    "$tool" --chip auto -p "$PORT" --before default_reset --after hard_reset \
        write_flash "$OFFSET" "$FILE" "$@"
    ;;

uf2) # Pico
    have picotool || die "picotool not installed"
    echo "[PICO] rebooting to BOOTSEL (ignore if already there)"
    picotool reboot -f || true
    echo "[PICO] loading: $FILE"
    picotool load -v -x "$FILE"
    echo "[PICO] rebooting app"
    picotool reboot || true
    ;;

hex) # Arduino AVR
    have avrdude || die "avrdude not installed"
    AVR_MCU="${AVR_MCU:-atmega328p}"
    AVR_BAUD="${AVR_BAUD:-115200}" # many old Nanos use 57600
    AVR_PROG="${AVR_PROG:-arduino}"
    echo "[AVR] mcu=$AVR_MCU prog=$AVR_PROG baud=$AVR_BAUD port=$PORT"
    avrdude -p "$AVR_MCU" -c "$AVR_PROG" -P "$PORT" -b "$AVR_BAUD" -D -U "flash:w:$FILE:i"
    ;;

py) # MicroPython file push
    have mpremote || die "mpremote not installed"
    echo "[MPY] copying $FILE to device"
    mpremote connect "$PORT" fs cp "$FILE" :/$(basename "$FILE")
    if [ "${RUN_AFTER_COPY:-0}" = "1" ]; then
        mpremote connect "$PORT" run "$FILE"
    fi
    ;;

*) die "unknown file type: .$EXT (supported: .bin .uf2 .hex .py)" ;;
esac

echo "[ok] done."
