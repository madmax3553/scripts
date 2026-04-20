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
# Script: perf-waybar.sh
# Purpose: Waybar module for CPU performance status
# Dependencies: jq, perf-mode
# Author: groot
# Modified: 2026-04-16

set -u
set -o pipefail

# Source waybar-cache if available for standard output formatting
# though for this simple check we can do it directly.
source "/home/groot/projects/scripts/lib/waybar-cache.sh"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
BOOST=$(cat /sys/devices/system/cpu/cpufreq/boost)
FREQ=$(grep "cpu MHz" /proc/cpuinfo | head -n 1 | awk '{print $4}')

ICON="󰓅"
CLASS="high"
TEXT="${FREQ%.*}MHz"

if [[ "$GOV" == "powersave" ]]; then
    ICON="󰈐"
    CLASS="low"
fi

if [[ "$BOOST" == "0" ]]; then
    CLASS="${CLASS}_noboost"
fi

TOOLTIP="Governor: $GOV\nBoost: $([[ "$BOOST" == "1" ]] && echo "Enabled" || echo "Disabled")\nFreq: $TEXT"

waybar_output "$ICON $TEXT" "$TOOLTIP" "$CLASS"
