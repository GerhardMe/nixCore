#!/usr/bin/env bash
exec >>/tmp/battery_debug.log 2>&1
echo "Battery monitor started at $(date)"

THRESHOLD=4
BATTERY_PATH="/sys/class/power_supply/BAT0/capacity"
STATUS_PATH="/sys/class/power_supply/BAT0/status"
POPUP_EXEC="$HOME/GNOMS/scripts/batNotify/battery_popup.run"
INTERVAL=61 # seconds between checks
STATE_FILE="/tmp/battery_warning_shown"

while true; do
    if [[ ! -f "$BATTERY_PATH" || ! -f "$STATUS_PATH" ]]; then
        echo "Battery path not found. Skipping check."
        sleep "$INTERVAL"
        continue
    fi

    BATTERY=$(cat "$BATTERY_PATH")
    STATUS=$(cat "$STATUS_PATH")

    echo "Battery: $BATTERY%, Status: $STATUS"

    if [[ "$BATTERY" -le "$THRESHOLD" && "$STATUS" != "Charging" ]]; then
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "Triggering popup..."
            "$POPUP_EXEC" &
            touch "$STATE_FILE"
        else
            echo "Popup already shown. Skipping."
        fi
    else
        if [[ -f "$STATE_FILE" ]]; then
            echo "Battery ok or charging. Resetting state."
            rm "$STATE_FILE"
        else
            echo "Battery ok. No popup needed."
        fi
    fi

    sleep "$INTERVAL"
done
