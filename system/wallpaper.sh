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
AWWW_SOCKET="/run/user/$(id -u)/wayland-1-awww-daemon.sock"
AWWW_WAIT_TIMEOUT=10  # Max seconds to wait for awww daemon

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# Function to check if awww daemon is running
is_awww_running() {
    if pgrep -x "awww-daemon" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Function to wait for awww daemon to be ready
wait_for_awww() {
    local timeout=$AWWW_WAIT_TIMEOUT
    local start_time=$(date +%s)

    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        if awww query >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done

    return 1
}

# Function to ensure awww daemon is running
ensure_awww_daemon() {
    if is_awww_running; then
        # Daemon is running, wait for it to be ready
        if wait_for_awww; then
            return 0
        else
            log_message "WARNING: awww daemon running but not responding, attempting restart..."
            pkill -x awww-daemon 2>/dev/null || true
            sleep 1
        fi
    fi

    # Start awww daemon
    log_message "Starting awww daemon..."
    awww-daemon >/dev/null 2>&1 &
    AWWW_PID=$!

    # Wait for daemon to be ready
    if wait_for_awww; then
        log_message "awww daemon started successfully (PID: $AWWW_PID)"
        return 0
    else
        log_message "ERROR: Failed to start or initialize awww daemon after ${AWWW_WAIT_TIMEOUT}s"
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

# Ensure awww daemon is running before starting rotation loop
ensure_awww_daemon || {
    log_message "FATAL: Cannot start awww daemon, exiting"
    exit 1
}

# Loop to rotate wallpapers
while true; do
    # Verify awww is still running before each rotation
    if ! is_awww_running; then
        log_message "WARNING: awww daemon died, attempting recovery..."
        if ! ensure_awww_daemon; then
            log_message "ERROR: Failed to recover awww daemon, skipping rotation"
            sleep $INTERVAL
            continue
        fi
    fi

    # Capture wallctl output for debugging
    if WALLCTL_OUTPUT=$(wallctl apply random 2>&1); then
        # Verify wallpaper was actually applied by checking awww
        if CURRENT_WALLPAPER=$(awww query 2>&1); then
            log_message "Wallpaper rotated: $WALLCTL_OUTPUT | Current: $CURRENT_WALLPAPER"
        else
            log_message "WARNING: wallctl succeeded but awww query failed: $CURRENT_WALLPAPER"
        fi
    else
        log_message "Error: wallctl apply random failed - $WALLCTL_OUTPUT"
    fi

    # Wait for interval
    sleep $INTERVAL
done
