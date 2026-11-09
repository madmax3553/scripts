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

LUA_CONFIG_FILE="${LUA_CONFIG_FILE:-/home/groot/.config/hypr/dynamic-monitors.lua}"
STATE_DIR="${STATE_DIR:-/home/groot/.local/state/hypr}"
LOG_FILE="${LOG_FILE:-$STATE_DIR/monitor-switch.log}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-1048576}" # 1 MiB

mkdir -p "$STATE_DIR"

rotate_log_if_needed() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if (( size > LOG_MAX_BYTES )); then
            mv -f "$LOG_FILE" "${LOG_FILE}.1"
        fi
    fi
}

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
    cat > "$LUA_CONFIG_FILE" << EOL
hl.monitor({ output = "$DOCKED_MONITOR", mode = "preferred", position = "auto", scale = "auto" })
hl.monitor({ output = "$MOBILE_MONITOR", disabled = true })
EOL
}

write_multi_config() {
    local monitor

    {
        while IFS= read -r monitor; do
            [[ -n "$monitor" ]] || continue
            printf 'hl.monitor({ output = "%s", mode = "preferred", position = "auto", scale = "auto" })\n' "$monitor"
        done <<< "$1"
        printf 'hl.monitor({ output = "%s", mode = "1920x1080", position = "auto", scale = 1 })\n' "$MOBILE_MONITOR"
    } > "$LUA_CONFIG_FILE"
}

write_mobile_config() {
    cat > "$LUA_CONFIG_FILE" << EOL
hl.monitor({ output = "$MOBILE_MONITOR", mode = "1920x1080", position = "auto", scale = 1 })
EOL
}

rotate_log_if_needed

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
  echo "APPLIED LUA CONFIG:"
  cat "$LUA_CONFIG_FILE"
  echo ""
} >> "$LOG_FILE"
