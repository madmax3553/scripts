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
# Script: monitor.sh
# Purpose: Hyprland monitor configuration
# Dependencies: hyprctl
# Author: groot
# Modified: 2026-01-24

set -euo pipefail
DOCKED_MONITOR="HDMI-A-1"
MOBILE_MONITOR="eDP-1"
DOCKED=0

CONFIG_FILE="/home/groot/.config/hypr/dynamic-monitors.conf"
LOG_FILE="/var/log/monitor-switch.log"

#Case flags to have systemd vs hyprctl
case "$1" in
    systemd)
        # Logic for systemd/boot
        for d in /sys/class/drm/*/status; do
            name=$(basename "$(dirname "$d")")
            status=$(cat "$d")
            if [[ "$name" == *"$DOCKED_MONITOR" ]] && [ "$status" = "connected" ]; then
                DOCKED=1
                break
            fi
        done

        if [ "$DOCKED" -eq 1 ]; then
            # Docked setup
            cat > "$CONFIG_FILE" << EOL
        monitor = $DOCKED_MONITOR, preferred, auto, auto
        monitor = $MOBILE_MONITOR, disable
EOL
        else
            # Mobile setup
            cat > "$CONFIG_FILE" << EOL
        monitor = $MOBILE_MONITOR, 1920x1080, auto, 1
EOL
        fi
        ;;
    hyprland)
        # Logic for when called from Hyprland
        # Get currently connected monitors
        CONNECTED=$(hyprctl monitors 2>/dev/null | awk '/^Monitor/{print $2}')
        echo "DEBUG: CONNECTED monitors: [$CONNECTED]" >> "$LOG_FILE"

        if echo "$CONNECTED" | grep -i "$DOCKED_MONITOR"; then
            # Docked setup
            cat > "$CONFIG_FILE" << EOL
        monitor = $DOCKED_MONITOR, preferred, auto, auto
        monitor = $MOBILE_MONITOR, disable
EOL
        else
            # Mobile setup
            cat > "$CONFIG_FILE" << EOL
        monitor = $MOBILE_MONITOR, 1920x1080, auto, 1
EOL
        fi

        ;;
    *)
        echo "Usage: $0 {systemd|hyprland}"
        exit 1
        ;;
esac

{
  echo "==== $(date) ===="
  echo "MODE: $1"
  echo "DOCKED: $DOCKED"
  echo "CONNECTED MONITORS:"
  if [ "$1" = "hyprland" ]; then
    echo "$CONNECTED"
  else
    for d in /sys/class/drm/*/status; do
      name=$(basename "$(dirname "$d")")
      status=$(cat "$d")
      echo "$name: $status"
    done
  fi
  echo "APPLIED CONFIG:"
  cat "$CONFIG_FILE"
  echo ""
} >> "$LOG_FILE"
