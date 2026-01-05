#!/usr/bin/env bash
set -Eeuo pipefail

notify() { command -v dunstify >/dev/null && dunstify "$1" "$2" || notify-send "$1" "$2" || true; }

handle_monitor() {
  sleep 0.5
  autorandr --change || true
  if command -v dunstify >/dev/null; then
    id=$(dunstify --action="arandr,Open layout editor" --urgency=normal --timeout=15000 --printid \
      "🖥️ Monitor change detected" "Click to configure" || true)
    if [ -n "$id" ] && [ "$(echo "$id" | sed -n 2p)" = "arandr" ]; then
      notify "💡 Enable autoconnection:" "autorandr --save setup_name"
      arandr >/dev/null 2>&1 &
    fi
  else
    notify "🖥️ Monitor change detected" "Run: autorandr --save <name> to persist"
  fi
}

handle_sleep() {
  "$HOME"/GNOM/scripts/blurlock.sh || true
}

inotifywait -mq -e create /tmp | while read -r _ _ file; do
  [[ "$file" =~ ^hw-trigger-[0-9]+-(.+)$ ]] || continue
  case "${BASH_REMATCH[1]}" in
  monitor) handle_monitor ;;
  sleep) handle_sleep ;;
  usb)
    "$HOME/GNOM/scripts/microcontroller-connect.sh" &
    ;;
  esac
done
