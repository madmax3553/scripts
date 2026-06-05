#!/usr/bin/env bash
# Script: battery-combined.sh
# Purpose: Combined battery and charge rate module for Waybar
# Dependencies: jq, cat, tr
# Author: groot
# Modified: 2026-06-05

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

BAT_PATH="/sys/class/power_supply/BAT0"
CHARGE_SCRIPT="/home/groot/projects/scripts/system/charge-rate.sh"

if [ ! -d "$BAT_PATH" ]; then
    waybar_output "No BAT" "Battery not found" "error"
    exit 0
fi

capacity=$(cat "$BAT_PATH/capacity")
status=$(cat "$BAT_PATH/status")

# Icons from config.jsonc
# Charging: 󰢜 󰂆 󰂇 󰂈 󰢝 󰂉 󰢞 󰂊 󰂋 󰂅
# Default:  󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹
get_icon() {
    local cap=$1
    local stat=$2
    local index=$((cap / 10))

    [ "$index" -gt 9 ] && index=9

    if [ "$stat" = "Charging" ]; then
        local icons=("󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅")
        echo "${icons[$index]}"
    else
        local icons=("󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")
        echo "${icons[$index]}"
    fi
}

icon=$(get_icon "$capacity" "$status")

if [ -x "$CHARGE_SCRIPT" ]; then
    charge_data=$("$CHARGE_SCRIPT" -j 2>/dev/null | tail -n1 || echo "{}")
    power=$(echo "$charge_data" | jq -r '.power_W // "0.00"')
    tooltip="${status}: ${capacity}% (${power}W)"
else
    tooltip="${status}: ${capacity}%"
fi

text="${capacity}% ${icon}"
class=$(echo "$status" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

waybar_output "$text" "$tooltip" "$class"
