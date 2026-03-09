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
# Purpose: Waybar yay updates indicator with caching
# Dependencies: yay, jq, flock, kitty, fuzzel (optional)
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

IGNORE_FILE="$HOME/.config/yay/ignored_packages"
CACHE_NAME="yay-updates"
STALE_THRESHOLD="${WAYBAR_STALE_THRESHOLD:-3600}"

DEFAULT_OUTPUT=$(waybar_output "⏳ Checking..." "Checking for updates..." "loading")

touch "$IGNORE_FILE"

get_ignored_packages() {
    tr '\n' ',' < "$IGNORE_FILE" 2>/dev/null | sed 's/,$//'
}

get_update_count() {
    local ignored="$1"
    if [ -n "$ignored" ]; then
        yay -Qu --ignore "$ignored" 2>/dev/null | wc -l
    else
        yay -Qu 2>/dev/null | wc -l
    fi
}

get_update_list() {
    local ignored="$1"
    if [ -n "$ignored" ]; then
        yay -Qu --ignore "$ignored" 2>/dev/null
    else
        yay -Qu 2>/dev/null
    fi
}

generate_output() {
    local ignored_packages update_count tooltip_text text
    ignored_packages=$(get_ignored_packages)
    update_count=$(get_update_count "$ignored_packages")

    if [ "$update_count" -gt 0 ]; then
        tooltip_text=$(get_update_list "$ignored_packages")
    else
        tooltip_text="No updates available"
    fi

    if [ -s "$IGNORE_FILE" ]; then
        tooltip_text="${tooltip_text}"$'\n'"Ignoring: $(get_ignored_packages)"
    fi

    text="${update_count} updates"
    waybar_output "$text" "$tooltip_text" ""
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

case "${1:-}" in
    update)
        if ! command -v yay >/dev/null 2>&1; then
            echo "yay not found" >&2
            exit 1
        fi
        ignored_packages=$(get_ignored_packages)
        kitty --title "yay-update" yay -Syyu --ignore "$ignored_packages"
        cache_clear "$CACHE_NAME"
        cache_update_with_lock "$CACHE_NAME" generate_output &
        ;;
    cache-clear)
        cache_clear "$CACHE_NAME"
        cache_update_with_lock "$CACHE_NAME" generate_output &
        ;;
    install)
        if ! command -v yay >/dev/null 2>&1; then
            echo "yay not found" >&2
            exit 1
        fi
        package=$(prompt_package)
        if [ -n "$package" ]; then
            kitty --title "yay-install" yay -S "$package"
            cache_clear "$CACHE_NAME"
            cache_update_with_lock "$CACHE_NAME" generate_output &
        fi
        ;;
    ignore)
        [ -n "${2:-}" ] && echo "$2" >> "$IGNORE_FILE"
        cache_clear "$CACHE_NAME"
        cache_update_with_lock "$CACHE_NAME" generate_output &
        ;;
    unignore)
        [ -n "${2:-}" ] && sed -i "/^$2$/d" "$IGNORE_FILE"
        cache_clear "$CACHE_NAME"
        cache_update_with_lock "$CACHE_NAME" generate_output &
        ;;
    *)
        if ! command -v yay >/dev/null 2>&1; then
            waybar_output "yay" "yay not installed" "error"
            exit 0
        fi

        output=$(cache_serve "$CACHE_NAME" generate_output "$STALE_THRESHOLD") || output="$DEFAULT_OUTPUT"
        echo "$output"
        ;;
esac
