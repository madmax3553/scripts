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
# Modified: 2026-02-14

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

# Use the helper script to generate output (avoids shell quoting issues)
GENERATE_CMD="/home/groot/projects/scripts/waybar/repostatus-generate.sh"

if [[ ! -x "$GENERATE_CMD" ]]; then
    waybar_output "Err!" "Helper script not found" "error"
    exit 0
fi

# Try to serve from cache, show default on first boot
output=$(cache_serve "$CACHE_NAME" "$GENERATE_CMD" "$STALE_THRESHOLD" "$DEFAULT_OUTPUT") || output="$DEFAULT_OUTPUT"
echo "$output"
