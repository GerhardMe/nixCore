#!/usr/bin/env bash

STEP=10       # Volume step in percentage
NOTIF_ID=8888 # arbitrary constant ID for replacement

VOL_STRING=$(wpctl get-volume @DEFAULT_SINK@)
CUR_VOL=$(awk '{ printf("%d\n", $2*10 + 0.5) }' <<<"$VOL_STRING")

if [[ "$1" == "up" ]]; then
    if ((CUR_VOL < 10)); then
        wpctl set-volume @DEFAULT_SINK@ $STEP%+
    fi
elif [[ "$1" == "down" ]]; then
    if ((CUR_VOL > 0)); then
        wpctl set-volume @DEFAULT_SINK@ $STEP%-
    fi
elif [[ "$1" == "mute" ]]; then
    wpctl set-mute @DEFAULT_SINK@ toggle
    awesome-client 'update_volume_icon()'
else
    echo "Usage: $0 [up|down|mute]"
    exit 1
fi

# Update with new volume
VOL_STRING=$(wpctl get-volume @DEFAULT_SINK@)
VOL=$(awk '{ printf("%d\n", $2*10 + 0.5) }' <<<"$VOL_STRING")

# Get if muted
ICON=󰕾
echo $(wpctl status @DEFAULT_SINK@ | grep "Sinks:" -A 1 | grep "MUTED")
if $(wpctl status @DEFAULT_SINK@ | grep "Sinks:" -A 1 | grep -q "MUTED"); then
    echo "muted"
    ICON=󰸈
fi

MUTED=$(wpctl status |
    grep -m1 'muted:' |
    awk -F'muted: ' '{print $2}' |
    awk '{print $1}')
echo $MUTE

FILLED=""
for ((i = 0; i < VOL; i++)); do
    FILLED+="▇"
done
EMPTY=$(
    for i in $(seq 1 $((10 - VOL))); do
        printf '%b' '\u00A0'
    done
)
BAR=" [ ${FILLED}${EMPTY} ] "

dunstify -r "${NOTIF_ID}" -t 1000 -h string:fgcolor:#00ffff "$ICON $BAR"
