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
# Script: yay-waybar.sh
# Purpose: Waybar yay updates indicator (reads from shared cache)
# Dependencies: yay, jq, flock, kitty, fuzzel (optional)
# Author: groot
# Modified: 2026-04-01

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

IGNORE_FILE="$HOME/.config/yay/ignored_packages"
CACHE_NAME="yay-updates"
STALE_THRESHOLD="${WAYBAR_STALE_THRESHOLD:-3600}"
DAEMON_CMD="/home/groot/projects/scripts/system/status-cache-daemon.sh"

DEFAULT_OUTPUT=$(waybar_output "⏳ Checking..." "Checking for updates..." "loading")

touch "$IGNORE_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions for actions that still need direct yay access
# ─────────────────────────────────────────────────────────────────────────────

get_ignored_packages() {
    tr '\n' ',' < "$IGNORE_FILE" 2>/dev/null | sed 's/,$//'
}

prompt_package() {
    local package=""
    if command -v fuzzel >/dev/null 2>&1; then
        package=$(printf '' | fuzzel --dmenu --prompt "Install package: " --width 40 --lines 0 2>/dev/null || true)
    else
        read -r -p "Install package: " package
    fi
    printf '%s' "$package"
}

trigger_refresh() {
    # Clear both the waybar-formatted and raw data caches, then refresh
    cache_clear "$CACHE_NAME"
    cache_clear "updates-data"
    if [[ -x "$DAEMON_CMD" ]]; then
        "$DAEMON_CMD" refresh-updates &
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Command dispatch
# ─────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
    update)
        if ! command -v yay >/dev/null 2>&1; then
            echo "yay not found" >&2
            exit 1
        fi
        ignored_packages=$(get_ignored_packages)
        kitty --title "yay-update" yay -Syyu --ignore "$ignored_packages"
        trigger_refresh
        ;;
    cache-clear)
        trigger_refresh
        ;;
    install)
        if ! command -v yay >/dev/null 2>&1; then
            echo "yay not found" >&2
            exit 1
        fi
        package=$(prompt_package)
        if [[ -n "$package" ]]; then
            kitty --title "yay-install" yay -S "$package"
            trigger_refresh
        fi
        ;;
    ignore)
        [[ -n "${2:-}" ]] && echo "$2" >> "$IGNORE_FILE"
        trigger_refresh
        ;;
    unignore)
        [[ -n "${2:-}" ]] && sed -i "/^$2$/d" "$IGNORE_FILE"
        trigger_refresh
        ;;
    *)
        if ! command -v yay >/dev/null 2>&1; then
            waybar_output "yay" "yay not installed" "error"
            exit 0
        fi

        # The daemon writes yay-updates.json (waybar-formatted).
        # Use cache_serve to read it, falling back to daemon refresh if stale.
        REFRESH_CMD="$DAEMON_CMD refresh-updates"
        output=$(cache_serve "$CACHE_NAME" "$REFRESH_CMD" "$STALE_THRESHOLD") || output="$DEFAULT_OUTPUT"

        # Validate JSON before sending to waybar -- malformed JSON causes waybar to crash
        if command -v jq >/dev/null 2>&1; then
            if ! echo "$output" | jq -e . >/dev/null 2>&1; then
                output="$DEFAULT_OUTPUT"
            fi
        fi
        echo "$output"
        ;;
esac
