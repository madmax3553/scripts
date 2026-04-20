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
# Script: perf-toggle.sh
# Purpose: Quick toggle between performance modes via Fuzzel
# Dependencies: fuzzel, perf-mode
# Author: groot
# Modified: 2026-04-16

set -e

# Configuration
# Use the stowed command name
PERF_MODE="perf-mode"

# Get current status to show in fuzzel
GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
BOOST=$(cat /sys/devices/system/cpu/cpufreq/boost)

OPTIONS="󰓅 High Performance\n󰈐 Low Power (Cool & Quiet)\n󰘳 Show TUI Menu"

CHOICE=$(echo -e "$OPTIONS" | fuzzel --dmenu --prompt="Perf ($GOV): " --width=30)

case "$CHOICE" in
    "󰓅 High Performance")
        # Notify first so user knows it's working
        notify-send "Performance" "Switching to High Performance..." -i speed-meter
        # perf-mode will handle the sudo call internaly
        if "$PERF_MODE" high; then
            notify-send "Performance" "Switched to High Performance mode" -i speed-meter
        else
            notify-send "Performance" "Failed to switch mode. Check sudo/polkit." -i dialog-error
        fi
        ;;
    "󰈐 Low Power (Cool & Quiet)")
        notify-send "Performance" "Switching to Low Power..." -i battery
        if "$PERF_MODE" low; then
            notify-send "Performance" "Switched to Low Power mode" -i battery
        else
            notify-send "Performance" "Failed to switch mode. Check sudo/polkit." -i dialog-error
        fi
        ;;
    "󰘳 Show TUI Menu")
        # Launch in terminal
        ghostty -e "$PERF_MODE" menu
        ;;
esac
