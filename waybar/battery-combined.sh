#!/usr/bin/env bash
# Script: battery-combined.sh
# Purpose: Combined battery, charge rate, and care-band module for Waybar
# Dependencies: jq
# Author: groot
# Modified: 2026-11-13

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

BAT_PATH="/sys/class/power_supply/BAT0"
AC_PATH="/sys/class/power_supply/AC/online"
CHARGE_SCRIPT="/home/groot/projects/scripts/system/charge-rate.sh"

read_sysfs() {
    local path="$1"
    local fallback="${2:-}"
    if [[ -r "$path" ]]; then
        cat "$path"
        return
    fi
    printf '%s' "$fallback"
}

# Icons from config.jsonc
# Charging: 󰢜 󰂆 󰂇 󰂈 󰢝 󰂉 󰢞 󰂊 󰂋 󰂅
# Default:  󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹
get_icon() {
    local cap=$1
    local stat=$2
    local index=$((cap / 10))
    local icons

    (( index > 9 )) && index=9

    if [[ "$stat" == "Charging" ]]; then
        icons=("󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅")
    else
        icons=("󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")
    fi
    printf '%s' "${icons[$index]}"
}

if [[ ! -d "$BAT_PATH" ]]; then
    waybar_output "No BAT" "Battery not found" "error"
    exit 0
fi

capacity=$(read_sysfs "$BAT_PATH/capacity" "?")
status=$(read_sysfs "$BAT_PATH/status" "Unknown")
start=$(read_sysfs "$BAT_PATH/charge_control_start_threshold")
stop=$(read_sysfs "$BAT_PATH/charge_control_end_threshold")
ac_online=$(read_sysfs "$AC_PATH" "0")

if [[ "$capacity" =~ ^[0-9]+$ ]]; then
    icon=$(get_icon "$capacity" "$status")
else
    icon="󰂃"
fi

power="0.00"
if [[ -x "$CHARGE_SCRIPT" ]]; then
    charge_data=$("$CHARGE_SCRIPT" -j 2>/dev/null | tail -n1 || true)
    if [[ -n "${charge_data:-}" ]]; then
        power=$(printf '%s' "$charge_data" | jq -r '.power_W // "0.00"' 2>/dev/null || echo "0.00")
    fi
fi

tooltip="${status}: ${capacity}% (${power}W)"
text="${capacity}% ${icon}"
class=$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
care_note=""

if [[ "$start" =~ ^[0-9]+$ && "$stop" =~ ^[0-9]+$ ]]; then
    text="${text} ${start}-${stop}"
    tooltip="${tooltip}"$'\n'"Care band: ${start}-${stop}%"$'\n'"Click to charge to 100%."

    if [[ "$status" == "Charging" ]]; then
        care_note="Stops at ${stop}%."
    elif [[ "$status" == "Discharging" ]]; then
        care_note="On AC, charges up to ${stop}%."
    elif [[ "$ac_online" == "1" && "$capacity" =~ ^[0-9]+$ ]] && (( capacity >= start )); then
        # Held by the firmware band, not a charge fault.
        class="care"
        if (( capacity >= stop )); then
            care_note="Above ${stop}%. Unplug to use it down; charging resumes below ${start}%."
        else
            care_note="In the hold window. Charging resumes below ${start}%."
        fi
    elif [[ "$ac_online" == "1" && "$capacity" =~ ^[0-9]+$ ]] && (( capacity < start )); then
        care_note="Below ${start}% on AC, but not charging."
    fi
fi

if [[ -n "$care_note" ]]; then
    tooltip="${tooltip}"$'\n'"${care_note}"
fi

waybar_output "$text" "$tooltip" "$class"
