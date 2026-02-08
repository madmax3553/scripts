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
# Script: wallpaper.sh
# Purpose: Wallpaper rotation daemon using wallctl
# Dependencies: wallctl
# Author: groot
# Modified: 2026-02-08

set -euo pipefail

INTERVAL=300  # Time between changes (seconds, 300 = 5 minutes)
LOG_FILE="$HOME/.cache/wallpaper.log"  # Log file for debugging

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Check if script is already running and kill it
SCRIPT_NAME=$(basename "$0")
PID=$(pgrep -o -f "$SCRIPT_NAME" 2>/dev/null || echo "")
if [ "$PID" != "$$" ] && [ -n "$PID" ]; then
    log_message "Killing existing script instance (PID: $PID)"
    kill "$PID" 2>/dev/null || true
    sleep 1
fi

log_message "Wallpaper rotation daemon started"

# Loop to rotate wallpapers
while true; do
    if wallctl apply random >/dev/null 2>&1; then
        log_message "Wallpaper rotated"
    else
        log_message "Error: wallctl apply random failed"
    fi

    # Wait for interval
    sleep $INTERVAL
done
