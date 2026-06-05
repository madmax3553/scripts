#!/usr/bin/env bash
# Script: system-resources.sh
# Purpose: Combined CPU performance and memory module for Waybar
# Dependencies: cat, grep, awk, cut, top, free
# Author: groot
# Modified: 2026-06-05

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
BOOST=$(cat /sys/devices/system/cpu/cpufreq/boost)
FREQ=$(grep "cpu MHz" /proc/cpuinfo | head -n 1 | awk '{print $4}')
FREQ_MHZ="${FREQ%.*}"

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | cut -d. -f1)

MEM_DATA=$(free | grep Mem)
MEM_TOTAL=$(echo "$MEM_DATA" | awk '{print $2}')
MEM_USED=$(echo "$MEM_DATA" | awk '{print $3}')
MEM_PCT=$((100 * MEM_USED / MEM_TOTAL))

PERF_ICON="󰓅"
PERF_CLASS="high"
if [[ "$GOV" == "powersave" ]]; then
    PERF_ICON="󰈐"
    PERF_CLASS="low"
fi
[[ "$BOOST" == "0" ]] && PERF_CLASS="${PERF_CLASS}_noboost"

text="${PERF_ICON} ${CPU_USAGE}% 󰍛 ${MEM_PCT}%"

tooltip="<b>CPU Profile:</b> ${GOV} (Boost: $([[ "$BOOST" == "1" ]] && echo "On" || echo "Off"))"$'\n'
tooltip+="<b>Frequency:</b> ${FREQ_MHZ} MHz"$'\n'
tooltip+="<b>CPU Usage:</b> ${CPU_USAGE}%"$'\n'
tooltip+="<b>Memory Usage:</b> ${MEM_PCT}% ($((MEM_USED / 1024))MB / $((MEM_TOTAL / 1024))MB)"

waybar_output "$text" "$tooltip" "$PERF_CLASS"
