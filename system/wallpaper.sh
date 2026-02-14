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
SWWW_SOCKET="/run/user/$(id -u)/swww-wayland.sock"
SWWW_WAIT_TIMEOUT=10  # Max seconds to wait for swww daemon

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Function to check if swww daemon is running
is_swww_running() {
    if pgrep -x "swww-daemon" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Function to wait for swww daemon to be ready
wait_for_swww() {
    local timeout=$SWWW_WAIT_TIMEOUT
    local start_time=$(date +%s)

    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        if swww query >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done

    return 1
}

# Function to ensure swww daemon is running
ensure_swww_daemon() {
    if is_swww_running; then
        # Daemon is running, wait for it to be ready
        if wait_for_swww; then
            return 0
        else
            log_message "WARNING: swww daemon running but not responding, attempting restart..."
            pkill -x swww-daemon 2>/dev/null || true
            sleep 1
        fi
    fi

    # Start swww daemon
    log_message "Starting swww daemon..."
    swww-daemon >/dev/null 2>&1 &
    SWWW_PID=$!

    # Wait for daemon to be ready
    if wait_for_swww; then
        log_message "swww daemon started successfully (PID: $SWWW_PID)"
        return 0
    else
        log_message "ERROR: Failed to start or initialize swww daemon after ${SWWW_WAIT_TIMEOUT}s"
        return 1
    fi
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

# Ensure swww daemon is running before starting rotation loop
ensure_swww_daemon || {
    log_message "FATAL: Cannot start swww daemon, exiting"
    exit 1
}

# Loop to rotate wallpapers
while true; do
    # Verify swww is still running before each rotation
    if ! is_swww_running; then
        log_message "WARNING: swww daemon died, attempting recovery..."
        if ! ensure_swww_daemon; then
            log_message "ERROR: Failed to recover swww daemon, skipping rotation"
            sleep $INTERVAL
            continue
        fi
    fi

    # Capture wallctl output for debugging
    if WALLCTL_OUTPUT=$(wallctl apply random 2>&1); then
        # Verify wallpaper was actually applied by checking swww
        if CURRENT_WALLPAPER=$(swww query 2>&1); then
            log_message "Wallpaper rotated: $WALLCTL_OUTPUT | Current: $CURRENT_WALLPAPER"
        else
            log_message "WARNING: wallctl succeeded but swww query failed: $CURRENT_WALLPAPER"
        fi
    else
        log_message "Error: wallctl apply random failed - $WALLCTL_OUTPUT"
    fi

    # Wait for interval
    sleep $INTERVAL
done
