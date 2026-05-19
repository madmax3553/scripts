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
# Modified: 2026-05-14

set -euo pipefail
MOBILE_MONITOR="eDP-1"
DOCKED_MONITOR=""
DOCKED=0
MODE="hyprland"
MULTI_MONITOR=0
CONNECTED=""

CONFIG_FILE="${CONFIG_FILE:-/home/groot/.config/hypr/dynamic-monitors.conf}"
LOG_FILE="${LOG_FILE:-/var/log/monitor-switch.log}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [systemd|hyprland] [--multi]

  systemd    Use /sys/class/drm detection
  hyprland   Use hyprctl detection (default)
  --multi    Enable all external monitors and keep eDP-1 enabled
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        systemd|hyprland)
            MODE="$1"
            ;;
        -m|--multi|multi)
            MULTI_MONITOR=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
    shift
done

list_external_sysfs() {
    local d name monitor status

    for d in /sys/class/drm/*/status; do
        [[ -e "$d" ]] || continue
        name=$(basename "$(dirname "$d")")
        monitor="${name#card*-}"
        status=$(cat "$d")
        if [[ "$status" = "connected" && "$monitor" != "$MOBILE_MONITOR" ]]; then
            printf '%s\n' "$monitor"
        fi
    done
}

find_external_sysfs() {
    local monitor

    while IFS= read -r monitor; do
        if [[ -n "$monitor" ]]; then
            printf '%s\n' "$monitor"
            return 0
        fi
    done <<< "$(list_external_sysfs)"

    return 1
}

list_external_hyprland() {
    local monitor

    while IFS= read -r monitor; do
        if [[ -n "$monitor" && "$monitor" != "$MOBILE_MONITOR" ]]; then
            printf '%s\n' "$monitor"
        fi
    done <<< "$CONNECTED"
}

find_external_hyprland() {
    local monitor

    while IFS= read -r monitor; do
        if [[ -n "$monitor" ]]; then
            printf '%s\n' "$monitor"
            return 0
        fi
    done <<< "$(list_external_hyprland)"

    return 1
}

write_docked_config() {
    cat > "$CONFIG_FILE" << EOL
        monitor = $DOCKED_MONITOR, preferred, auto, auto
        monitor = $MOBILE_MONITOR, disable
EOL
}

write_multi_config() {
    local monitor

    {
        while IFS= read -r monitor; do
            [[ -n "$monitor" ]] || continue
            printf '        monitor = %s, preferred, auto, auto\n' "$monitor"
        done <<< "$1"
        printf '        monitor = %s, 1920x1080, auto, 1\n' "$MOBILE_MONITOR"
    } > "$CONFIG_FILE"
}

write_mobile_config() {
    cat > "$CONFIG_FILE" << EOL
        monitor = $MOBILE_MONITOR, 1920x1080, auto, 1
EOL
}

#Case flags to have systemd vs hyprctl
case "$MODE" in
    systemd)
        # Logic for systemd/boot
        if DOCKED_MONITOR=$(find_external_sysfs); then
            DOCKED=1
        fi

        if [ "$DOCKED" -eq 1 ]; then
            # Docked setup
            if [ "$MULTI_MONITOR" -eq 1 ]; then
                write_multi_config "$(list_external_sysfs)"
            else
                write_docked_config
            fi
        else
            # Mobile setup
            write_mobile_config
        fi
        ;;
    hyprland)
        # Logic for when called from Hyprland
        # Get currently connected monitors
        CONNECTED=$(hyprctl monitors all 2>/dev/null | awk '/^Monitor/{print $2}')
        echo "DEBUG: CONNECTED monitors: [$CONNECTED]" >> "$LOG_FILE"

        if DOCKED_MONITOR=$(find_external_hyprland); then
            DOCKED=1
            # Docked setup
            if [ "$MULTI_MONITOR" -eq 1 ]; then
                write_multi_config "$(list_external_hyprland)"
            else
                write_docked_config
            fi
        else
            # Mobile setup
            write_mobile_config
        fi

        ;;
    *)
        usage >&2
        exit 1
        ;;
esac

{
  echo "==== $(date) ===="
  echo "MODE: $MODE"
  echo "MULTI_MONITOR: $MULTI_MONITOR"
  echo "DOCKED: $DOCKED"
  echo "CONNECTED MONITORS:"
  if [ "$MODE" = "hyprland" ]; then
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
