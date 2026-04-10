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
# Purpose: Waybar repo status indicator (reads from shared cache)
# Dependencies: jq, status-cache-daemon.sh
# Author: groot
# Modified: 2026-03-20

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

CACHE_NAME="repostatus"
STALE_THRESHOLD="${WAYBAR_STALE_THRESHOLD:-300}"

DEFAULT_OUTPUT=$(waybar_output "⏳ Loading..." "Scanning repositories..." "loading")

if ! command -v jq >/dev/null 2>&1; then
    waybar_output "repo" "jq not installed" "error"
    exit 0
fi

# The daemon writes both repos-data.json (raw) and repostatus.json (waybar-formatted).
# We read the waybar-formatted cache directly. If stale, kick off a daemon refresh.
DAEMON_CMD="/home/groot/projects/scripts/system/status-cache-daemon.sh refresh-repos"

# Fallback: if no daemon cache exists, use the old generate script directly
GENERATE_CMD="/home/groot/projects/scripts/waybar/repostatus-generate.sh"
FALLBACK_CMD="$GENERATE_CMD"
if [[ -x "$DAEMON_CMD" ]] || command -v status-cache-daemon.sh >/dev/null 2>&1; then
    FALLBACK_CMD="$DAEMON_CMD"
fi

output=$(cache_serve "$CACHE_NAME" "$FALLBACK_CMD" "$STALE_THRESHOLD" "$DEFAULT_OUTPUT") || output="$DEFAULT_OUTPUT"
echo "$output"
