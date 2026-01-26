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
# Script: charge-waybar.sh
# Purpose: Waybar wrapper for charge-rate.sh
# Dependencies: jq, notify-send (optional)
# Author: Custom
# Modified: 2026-01-24

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

charge_cmd="/home/groot/projects/scripts/system/charge-rate.sh"

if [ ! -x "$charge_cmd" ]; then
    waybar_output "battery" "charge-rate.sh not found" "error"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    waybar_output "battery" "jq not installed" "error"
    exit 0
fi

data=$($charge_cmd -j | tail -n1)
if [ -z "$data" ]; then
    waybar_output "battery" "no data" "error"
    exit 0
fi

power=$(echo "$data" | jq -r '.power_W // empty')
status=$(echo "$data" | jq -r '.status // empty')
pct=$(echo "$data" | jq -r '.capacity_pct // empty')
class=$(echo "$status" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
text="${power}W"
tooltip="${status} ${pct}%"

if [ "$status" = "Charging" ] && awk "BEGIN{exit !(${power:-0} < 5)}"; then
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u low "Low charge rate" "Only ${power}W"
    fi
fi

waybar_output "$text" "$tooltip" "$class"
