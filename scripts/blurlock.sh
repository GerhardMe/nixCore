#!/usr/bin/env bash

set -euo pipefail

# --- Conditions ---
# already locked?
if pgrep -x i3lock >/dev/null; then
  exit 0
fi

# uptime in seconds
UPTIME=$(awk '{print int($1)}' /proc/uptime)

# if system older than 50s, then exit
if ((UPTIME < 50)); then
  exit 0
fi

# --- your existing script follows ---

RADIUS=0x${1:-1}
IMG=/tmp/screenshot.png
OVER=/tmp/lock_overlay.png

FONTFILE="$(fc-list -f '%{file}\n' | grep -i -E 'SymbolsNerdFontMono|NerdFont.*Mono' | head -n1 || true)"
if [[ -z "${FONTFILE}" ]]; then
  dunstify -u critical "No Nerd Font found. Install a Nerd Font (e.g. Symbols Nerd Font Mono)."
  exit 1
fi

LOCK_CHAR=$'\ue672'
POINTSIZE=160
FILL="#BABABA"
STROKE="#292929"
STROKEWIDTH=2

dunstify -u normal -t 700 -h string:fgcolor:#00ffff "🔒 Locking Computer..."

maim -u | magick - -scale 10% -blur "$RADIUS" -resize 1000% "$IMG"

magick -size 600x600 xc:none \
  -gravity center \
  -fill "$FILL" -stroke "$STROKE" -strokewidth "$STROKEWIDTH" \
  -font "$FONTFILE" -pointsize "$POINTSIZE" \
  -annotate -1-6 "$LOCK_CHAR" \
  "$OVER"

if ! magick identify -format '%[channels]' "$OVER" >/dev/null 2>&1; then
  exit 1
fi

magick "$IMG" "$OVER" -gravity center -compose over -composite "$IMG"

exec i3lock -i "$IMG"
