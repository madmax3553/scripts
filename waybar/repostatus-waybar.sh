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
# Script: repostatus-waybar.sh
# Purpose: Waybar repo status indicator with caching
# Dependencies: jq, repostatus, flock
# Author: groot
# Modified: 2026-01-25

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

CACHE_NAME="repostatus"
STALE_THRESHOLD="${WAYBAR_STALE_THRESHOLD:-300}"

DEFAULT_OUTPUT=$(waybar_output "⏳ Loading..." "Scanning repositories..." "loading")

if ! command -v repostatus >/dev/null 2>&1; then
    waybar_output "Err!" "$PATH" "$USER"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    waybar_output "repo" "jq not installed" "error"
    exit 0
fi

generate_output() {
    local json_data overall_status status_counts repos
    json_data=$(repostatus --json-summary 2>/dev/null) || return 1
    [[ -z "$json_data" ]] && return 1

    overall_status=$(echo "$json_data" | jq -r '.overall_status // "unknown"')
    status_counts=$(echo "$json_data" | jq '.status_counts // {}')
    repos=$(echo "$json_data" | jq -c '.repos[]?' 2>/dev/null)

    local good_count dirty_count bad_count uninitialized_count
    good_count=$(echo "$status_counts" | jq -r '.clean // 0')
    dirty_count=$(( $(echo "$status_counts" | jq -r '.dirty // 0') + $(echo "$status_counts" | jq -r '.ahead // 0') ))
    bad_count=$(( $(echo "$status_counts" | jq -r '.behind // 0') + $(echo "$status_counts" | jq -r '.diverged // 0') ))
    uninitialized_count=$(echo "$status_counts" | jq -r '.uninitialized // 0')

    local green_color="#a6e3a1"
    local yellow_color="#f9e2af"
    local red_color="#f38ba8"
    local grey_color="#6c7086"

    local text
    text="<span foreground='$green_color'>●</span> $good_count <span foreground='$yellow_color'>●</span> $dirty_count <span foreground='$red_color'>●</span> $bad_count <span foreground='$grey_color'>●</span> $uninitialized_count"

    local tooltip=""
    if [ -n "$repos" ]; then
        while IFS= read -r repo; do
            local name status
            name=$(echo "$repo" | jq -r '.name')
            status=$(echo "$repo" | jq -r '.status')
            tooltip="$tooltip$name: $status\n"
        done <<< "$repos"
    fi

    if [ -z "$tooltip" ]; then
        tooltip="All repositories are clean."
    fi

    printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$text" "$overall_status" "$tooltip"
}

# Try to serve from cache, show default on first boot
output=$(cache_serve "$CACHE_NAME" generate_output "$STALE_THRESHOLD" "$DEFAULT_OUTPUT") || output="$DEFAULT_OUTPUT"
echo "$output"
