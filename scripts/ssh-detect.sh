#!/usr/bin/env bash
set -euo pipefail

ORANGE="#ff8c00"
BLUE="#002199"   # your normal bar color

ssh_count() {
  local cnt=0
  while read -r sid _; do
    [[ -n "$sid" ]] || continue
    local info
    info="$(loginctl show-session "$sid" -p Service -p Remote -p State 2>/dev/null || true)"
    if grep -q '^Service=sshd$' <<<"$info" && \
       grep -q '^Remote=yes$' <<<"$info" && \
       grep -q '^State=active$' <<<"$info"; then
      cnt=$((cnt+1))
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
  echo "$cnt"
}

set_bar_color() {
  local color="$1"
  command -v awesome-client >/dev/null || return 0
  [[ -z "${DISPLAY:-}" ]] && return 0
  awesome-client "awesome.emit_signal('mode::bar_bg', '$color')" >/dev/null 2>&1 || true
}

notify() {
  command -v dunstify >/dev/null || return 0
  dunstify -a "ssh" "$1" "$2" -u low -t 2000 >/dev/null 2>&1 || true
}

last="$(ssh_count)"
if (( last > 0 )); then
  set_bar_color "$ORANGE"
else
  set_bar_color "$BLUE"
fi

while inotifywait -q -e modify /run/utmp >/dev/null 2>&1; do
  sleep 0.05
  now="$(ssh_count)"
  if (( now != last )); then
    if (( now > 0 )); then
      set_bar_color "$ORANGE"
      notify "SSH connected" "$now active session(s)"
    else
      set_bar_color "$BLUE"
      notify "SSH disconnected" "No active SSH sessions"
    fi
    last="$now"
  fi
done
