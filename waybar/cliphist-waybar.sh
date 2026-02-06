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
# Script: cliphist-waybar.sh
# Purpose: Waybar clipboard indicator with hover preview
# Dependencies: cliphist, wl-clipboard, jq
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

if ! command -v wl-paste >/dev/null 2>&1; then
    waybar_output "󰅇" "wl-paste not installed" "error"
    exit 0
fi

if ! command -v cliphist >/dev/null 2>&1; then
    waybar_output "󰅇" "cliphist not installed" "error"
    exit 0
fi

content=$(wl-paste --type text 2>/dev/null || true)
if [ -z "$content" ]; then
    content="(empty)"
fi

preview=$(printf '%s' "$content" | tr '\n' ' ' | sed 's/  */ /g')
preview=$(printf '%s' "$preview" | cut -c1-200)

waybar_output "󰅇" "Clipboard: $preview" ""
