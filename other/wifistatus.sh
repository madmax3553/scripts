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
# Script: wifistatus.sh
# Purpose: Waybar WiFi status indicator
# Dependencies: nmcli
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

if ! command -v nmcli >/dev/null 2>&1; then
    waybar_output "wifi" "nmcli not installed" "error"
    exit 0
fi

ssid=$(nmcli -t -f ACTIVE,SSID dev wifi | awk -F: '$1=="yes" {print $2; exit}')

if [ -z "$ssid" ]; then
    waybar_output "📡" "Wi-Fi: Disconnected" "disconnected"
else
    waybar_output "📶" "Wi-Fi: $ssid" "connected"
fi
