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
# Script: perf-mode.sh
# Purpose: Toggle CPU performance profiles for Ryzen 3500U
# Dependencies: cpupower, bash, dialog
# Author: groot
# Modified: 2026-04-16

set -e

# Source colors
source "/home/groot/projects/scripts/lib/colors.sh"

# Configuration
LOW_GOVERNOR="powersave"
HIGH_GOVERNOR="performance"
BOOST_PATH="/sys/devices/system/cpu/cpufreq/boost"

# Dark theme for dialog - precisely matching repostatus
export DIALOGRC=""
export DIALOG_COLOR="on"
DIALOG_THEME=$(mktemp)
cat > "$DIALOG_THEME" << 'EOF'
aspect = 0
separate_widget = ""
tab_len = 0
visit_items = OFF
use_shadow = ON
use_colors = ON
screen_color = (CYAN,DEFAULT,OFF)
shadow_color = (DEFAULT,DEFAULT,OFF)
dialog_color = (CYAN,DEFAULT,OFF)
title_color = (CYAN,DEFAULT,ON)
border_color = (CYAN,DEFAULT,OFF)
border2_color = (CYAN,DEFAULT,OFF)
button_active_color = (BLACK,CYAN,OFF)
button_inactive_color = (CYAN,DEFAULT,OFF)
button_key_active_color = (BLACK,CYAN,OFF)
button_key_inactive_color = (CYAN,DEFAULT,OFF)
button_label_active_color = (BLACK,CYAN,OFF)
button_label_inactive_color = (CYAN,DEFAULT,OFF)
menubox_color = (CYAN,DEFAULT,OFF)
menubox_border_color = (CYAN,DEFAULT,OFF)
menubox_border2_color = (CYAN,DEFAULT,OFF)
item_color = (CYAN,DEFAULT,OFF)
item_selected_color = (BLACK,CYAN,OFF)
tag_color = (CYAN,DEFAULT,OFF)
tag_selected_color = (BLACK,CYAN,OFF)
tag_key_color = (CYAN,DEFAULT,OFF)
tag_key_selected_color = (BLACK,CYAN,OFF)
gauge_color = (CYAN,DEFAULT,OFF)
EOF
export DIALOGRC="$DIALOG_THEME"

cleanup() {
    rm -f "$DIALOG_THEME"
}
trap cleanup EXIT

get_status_text() {
    local gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    local boost=$(cat "$BOOST_PATH")
    local cur_freq=$(grep "cpu MHz" /proc/cpuinfo | head -n 1 | awk '{print $4}')
    local max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)
    
    printf "Governor:     %s\n" "$gov"
    printf "AMD Boost:    %s\n" "$( [[ "$boost" == "1" ]] && echo "ENABLED" || echo "DISABLED" )"
    printf "Max Freq:     %s MHz\n" "$(expr $max_freq / 1000)"
    printf "Current:      ~%s MHz\n" "${cur_freq%.*}"
}

set_mode() {
    local mode=$1
    
    # Auto-elevate if not root, but DON'T exec to keep shell alive
    if [[ "$EUID" -ne 0 ]]; then
        # We use a terminal for elevation if possible, or just sudo
        # If in terminal (dialog), sudo will prompt there.
        # If from waybar/fuzzel, we need a way to prompt.
        if [[ -t 0 ]]; then
            sudo "$0" "$mode" >/dev/null 2>&1
        else
            # Try to use a polkit agent if available for background tasks
            # or just hope the user has NOPASSWD or a GUI agent.
            sudo "$0" "$mode" >/dev/null 2>&1
        fi
        return
    fi

    case "$mode" in
        low)
            # Temporarily stop competing services
            systemctl stop auto-cpufreq tlp > /dev/null 2>&1 || true
            
            cpupower frequency-set -g "$LOW_GOVERNOR" > /dev/null
            echo 0 > "$BOOST_PATH"
            cpupower frequency-set -u 1400MHz > /dev/null
            ;;
        high)
            cpupower frequency-set -u 2100MHz > /dev/null
            cpupower frequency-set -g "$HIGH_GOVERNOR" > /dev/null
            echo 1 > "$BOOST_PATH"

            # Restart competing services to let them take over if needed
            systemctl start auto-cpufreq tlp > /dev/null 2>&1 || true
            ;;
    esac
}

menu() {
    local choice
    local status_msg
    status_msg=$(get_status_text)
    
    choice=$(dialog --clear \
                --title "Groot Performance Toggler" \
                --menu "$status_msg\n\nSelect a performance profile:" 18 60 4 \
                "High" "Full Performance (Boost ON)" \
                "Low"  "Cool & Quiet (1.4GHz Cap)" \
                "Status" "Refresh Status Info" \
                "Exit" "Close Toggler" \
                2>&1 >/dev/tty)

    case "$choice" in
        High) set_mode high; menu ;;
        Low) set_mode low; menu ;;
        Status) menu ;;
        *) clear; exit 0 ;;
    esac
}

case "${1:-menu}" in
    low|high) set_mode "$1" ;;
    status) get_status_text ;;
    menu) menu ;;
    *) menu ;;
esac
