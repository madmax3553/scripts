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
# Purpose: Wallpaper rotation using swww
# Dependencies: swww, identify
# Author: groot
# Modified: 2026-01-24

set -euo pipefail
shopt -s nullglob
WALLPAPER_DIR="$HOME/wallpapers/current"  # Active wallpaper rotation directory
FALLBACK_DIR="$HOME/wallpapers"  # Legacy wallpaper directory
INTERVAL=300  # Time between changes (seconds, 300 = 5 minutes)
LOG_FILE="$HOME/.cache/wallpaper.log"  # Log file for debugging
LANDSCAPE_ONLY=1

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

get_dimensions() {
    local file="$1"
    local dims
    dims=$(identify -ping -format '%w %h' "$file" 2>/dev/null || true)
    if [[ "$dims" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then
        printf '%s\n' "$dims"
    else
        printf '0 0\n'
    fi
}

build_candidates() {
    local dir="$1"
    local file w h
    local list=()
    for file in "$dir"/*.{jpg,jpeg,png,webp,gif}; do
        [[ -f "$file" ]] || continue
        if (( LANDSCAPE_ONLY == 1 )); then
            read -r w h <<< "$(get_dimensions "$file")"
            (( w >= h )) || continue
        fi
        list+=("$file")
    done
    printf '%s\n' "${list[@]}"
}

# Check if script is already running and kill it
SCRIPT_NAME=$(basename "$0")
PID=$(pgrep -o -f "$SCRIPT_NAME")
if [ "$PID" != "$$" ] && [ -n "$PID" ]; then
    log_message "Killing existing script instance (PID: $PID)"
    kill "$PID"
    sleep 1
fi

#if pgrep -x waypaper > /dev/null; then
#    log_message "Killing waypaper to prevent interference"
#    killall waypaper
#    sleep 1
#fi

# Initialize swww if not running
if ! pgrep -x swww-daemon > /dev/null; then
    log_message "Starting swww"
    swww-daemon &
    sleep 1
fi

# Loop to rotate wallpapers
while true; do
    # Get list of wallpapers
    mapfile -t wallpapers < <(build_candidates "$WALLPAPER_DIR")
    if [ ${#wallpapers[@]} -eq 0 ]; then
        mapfile -t wallpapers < <(build_candidates "$FALLBACK_DIR")
    fi
    if [ ${#wallpapers[@]} -eq 0 ]; then
        log_message "No wallpapers found in $WALLPAPER_DIR or $FALLBACK_DIR"
        sleep "$INTERVAL"
        continue
    fi

    # Randomly select a wallpaper
    wallpaper=${wallpapers[$RANDOM % ${#wallpapers[@]}]}

    # Set wallpaper with swww (wipe transition)
    if swww img "$wallpaper" --transition-type wipe --transition-duration 2; then
        log_message "Set wallpaper: $wallpaper"
    else
        log_message "Error: swww failed to set $wallpaper"
        sleep $INTERVAL
        continue
    fi

    # Theme generation removed (wallust deprecated)

    #Reload Waybar with SIGHUP, fallback to restart
    #if kill -SIGUSR2 $(pidof waybar) 2>/dev/null; then
    #    log_message "Waybar reloaded via SIGHUP"
    #else
    #    log_message "SIGHUP failed, restarting Waybar"
    #    if killall waybar 2>/dev/null; then
    #        sleep 0.1
    #        waybar & disown
    #        log_message "Waybar restarted"
    #    else
    #        log_message "Error: Failed to reload or restart Waybar"
    #    fi
    #fi

    # Load hyprpanel configuration
    # hyprpanel -rs

    # Wait for interval
    sleep $INTERVAL
done
