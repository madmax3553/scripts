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
# Author: groot
# Modified: 2026-01-24

set -u
set -o pipefail

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

# We don't use set -e here so we can handle the failure manually
data=$($charge_cmd -j 2>/dev/null | tail -n1 || true)

if [ -z "$data" ]; then
    waybar_output "No Data" "Battery script failed or returned no data" "error"
    exit 0
fi

power=$(echo "$data" | jq -r '.power_W // 0')
status=$(echo "$data" | jq -r '.status // "Unknown"')
pct=$(echo "$data" | jq -r '.capacity_pct // 0')
class=$(echo "$status" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
text="${power}W"
tooltip="${status} ${pct}%"

if [ "$status" = "Charging" ] && awk "BEGIN{exit !(${power:-0} < 5)}"; then
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u low "Low charge rate" "Only ${power}W"
    fi
fi

waybar_output "$text" "$tooltip" "$class"
