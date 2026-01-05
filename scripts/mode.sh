#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mode/state"
APPLIER="$HOME/GNOM/scripts/mode-set.sh"
PERF="$HOME/GNOM/scripts/performance.sh"

usage() {
  echo "Usage: mode {server|normal|performance|status}"
  exit 1
}

mkdir -p "$(dirname "$STATE_FILE")"
prev="normal"
[[ -f "$STATE_FILE" ]] && prev="$(tr -d ' \t\r\n' <"$STATE_FILE" || echo normal)"

case "${1:-}" in
server | normal | performance)
  new="$1"

  # Handle performance transitions BEFORE applying the rest
  if [[ "$prev" != "performance" && "$new" == "performance" ]]; then
    [[ -x "$PERF" ]] || {
      echo "Error: $PERF not found/executable"
      exit 1
    }
    "$PERF" enable
  elif [[ "$prev" == "performance" && "$new" != "performance" ]]; then
    [[ -x "$PERF" ]] || {
      echo "Error: $PERF not found/executable"
      exit 1
    }
    "$PERF" disable
  fi

  # Persist and apply the new mode
  printf '%s\n' "$new" >"$STATE_FILE"
  [[ -x "$APPLIER" ]] || {
    echo "Error: $APPLIER not found/executable"
    exit 1
  }
  exec "$APPLIER"
  ;;

status)
  [[ -x "$APPLIER" ]] || {
    echo "Error: $APPLIER not found/executable"
    exit 1
  }
  exec "$APPLIER"
  ;;

*)
  usage
  ;;
esac
