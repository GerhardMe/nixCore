#!/usr/bin/env bash

# --- helpers ---------------------------------------------------------------

pick_serial_port() {
  # Prefer newest ACM/USB device
  ls -t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n1
}

is_micropython_port() {
  local port="$1"
  command -v mpremote >/dev/null 2>&1 || return 1
  mpremote devs 2>/dev/null | grep -q "$port" || return 1
  mpremote connect "$port" exec "print('MPY')" 2>/dev/null | grep -q "MPY"
}

is_esp_port() {
  local port="$1"
  command -v esptool.py >/dev/null 2>&1 || return 1
  # Quick probe; success exit or recognizable output => ESP present
  esptool.py --chip auto --port "$port" chip_id >/tmp/esp_probe.log 2>&1
  grep -Eq "Detecting chip type|Chip is|Features:" /tmp/esp_probe.log
}

spawn_wezterm_title_once() {
  # Title-based singleton: if a wezterm with that title exists, don’t spawn
  local title="$1"
  shift
  local cmd="$*"
  if xdotool search --name "^${title}$" >/dev/null 2>&1; then
    echo "[info] ${title} already running"
  else
    echo "[spawn] ${title}: $cmd"
    wezterm --class "$title" --title "$title" bash -lc "$cmd" &
  fi
}

# --- your existing monitor handler stays as-is -----------------------------
handle_monitor() {
  sleep 0.5
  autorandr --change
  id=$(dunstify --action="arandr,Open layout editor" \
    --urgency=normal \
    --timeout=15000 \
    --printid \
    "🖥️ Monitor change detected" "Click to configure")
  if [ -n "$id" ]; then
    action=$(echo "$id" | sed -n 2p)
    if [ "$action" = "arandr" ]; then
      notify-send "💡 Enable autoconection:" "autorandr --save setup_name"
      arandr &
    fi
  fi
}

# --- upgraded USB handler --------------------------------------------------
handle_usb() {
  sleep 0.5 # Let USB settle

  PORT=$(pick_serial_port)
  if [[ -z "$PORT" ]]; then
    echo "[error] No /dev/ttyACM* or /dev/ttyUSB* found"
    return
  fi
  echo "[detect] Candidate port: $PORT"

  # 1) MicroPython path (your original flow, unchanged behavior)
  if is_micropython_port "$PORT"; then
    echo "[match] MicroPython on $PORT"
    # REPL window singleton
    REPL_WIN_ID=$(xdotool search --name "^Pico Console$" 2>/dev/null | head -n1)
    if [[ -n "$REPL_WIN_ID" ]]; then
      echo "[info] MicroPython REPL already running"
    else
      spawn_wezterm_title_once "Pico Console" "while true; do mpremote connect $PORT repl; sleep 3; done"
    fi
    notify-send "🐍 MicroPython device detected" "To run a program:\n\nmcflash path/to/program.py"
    return
  fi

  # 2) ESP (typical C toolchains) via esptool probe
  if is_esp_port "$PORT"; then
    echo "[match] ESP device on $PORT"
    # Prefer idf.py monitor if present; otherwise use pyserial miniterm
    if command -v idf.py >/dev/null 2>&1; then
      spawn_wezterm_title_once "ESP Monitor" "idf.py -p $PORT monitor"
      notify-send "⚙️ ESP device detected" "Opened IDF monitor on $PORT.\nFlash example:\nidf.py -p $PORT flash monitor"
    else
      # Fallback monitor; requires 'pip install pyserial'
      spawn_wezterm_title_once "ESP Monitor" "python -m serial.tools.miniterm $PORT 115200 --eol LF"
      notify-send "⚙️ ESP device detected" "Opened serial monitor 115200 on $PORT.\nFlash example:\nesptool.py --chip auto --port $PORT write_flash 0x10000 firmware.bin"
    fi
    return
  fi

  # 3) Unknown serial device; just notify and do nothing
  echo "[skip] Unknown/non-ESP/non-MPY serial device on $PORT"
  notify-send "🔌 Serial device connected" "Port: $PORT\n(Unsupported type: not MicroPython, no ESP detected)"
}
