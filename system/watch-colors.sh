#!/usr/bin/env bash
#  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓
# ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒
#▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░
#░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ 
#░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ 
# ░▒   ▒ ░ ▒▓ ░▒▓░░ ░▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   
#  ░   ░   ░▒ ░ ▒░  ░ ░ ░ ░ ░   ░ ░ ░   ░    
#░ ░   ░   ░░   ░ ░ ░ ░ ░ ░ ░ ░ ░ ░   ░      
#      ░    ░         ░ ░      ░ ░           
# Script: watch-colors.sh
# Purpose: Watch colorscheme file and auto-sync on changes
# Dependencies: inotify-tools, sync-colors.sh
# Author: groot
# Modified: 2026-02-28

set -euo pipefail

COLORS_FILE="${HOME}/.config/colorscheme/cyberdream.json"
SYNC_SCRIPT="${HOME}/.config/colorscheme/sync-colors.sh"

if ! command -v inotifywait &> /dev/null; then
    echo "❌ inotify-tools not installed. Install with: yay -S inotify-tools"
    exit 1
fi

echo "👁️  Watching $COLORS_FILE for changes..."
echo "Press Ctrl+C to stop."

inotifywait -m -e modify "$COLORS_FILE" |
while read path action file; do
    echo "[$action] Detected change to $file"
    "$SYNC_SCRIPT"
    echo "🔄 Restarting dunst and waybar..."
    killall -SIGUSR1 dunst 2>/dev/null || true
    killall -SIGUSR2 waybar 2>/dev/null || true
done
