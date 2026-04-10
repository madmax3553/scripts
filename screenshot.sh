#!/usr/bin/env bash
#  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓
# ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒
#▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░
#░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░
#░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░
# ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░
#  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░
#░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░
#      ░    ░         ░ ░      ░ ░
# Script: screenshot.sh
# Purpose: Capture screenshots, save to disk, copy to clipboard, and offer open/edit actions
# Dependencies: grim, slurp, wl-copy, notify-send, swappy, hyprctl, jq, xdg-open
# Author: groot

set -euo pipefail

mode=${1:-area}
dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
file="$dir/Screenshot_${timestamp}.png"

mkdir -p "$dir"

notify() {
  local title="$1"
  local body="$2"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send \
      --app-name="Screenshot" \
      --icon="$file" \
      --action="open=Open" \
      --action="edit=Edit" \
      "$title" "$body" | while IFS= read -r action; do
        case "$action" in
          open)
            xdg-open "$file" >/dev/null 2>&1 &
            ;;
          edit)
            swappy -f "$file" >/dev/null 2>&1 &
            ;;
        esac
      done
  fi
}

capture_area() {
  local geometry
  geometry=$(slurp) || exit 0
  grim -g "$geometry" - | tee "$file" | wl-copy
}

capture_window() {
  local geometry
  geometry=$(hyprctl -j activewindow | jq -r 'select(.at and .size) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
  [[ -n "$geometry" ]] || exit 1
  grim -g "$geometry" - | tee "$file" | wl-copy
}

capture_screen() {
  grim - | tee "$file" | wl-copy
}

case "$mode" in
  area)
    capture_area
    ;;
  window)
    capture_window
    ;;
  screen)
    capture_screen
    ;;
  *)
    exit 1
    ;;
esac

notify "Screenshot saved" "$file"
