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
# Script: wifi.sh
# Purpose: WiFi AP selector using nmcli and fuzzel
# Dependencies: nmcli, fuzzel, notify-send
# Author: groot

set -euo pipefail

# ===== Configuration =====
FUZZEL_OPTS="--dmenu --prompt '  ' --width 45 --lines 12"

notify() {
    notify-send "WiFi" "$1"
}

# 1. Check if WiFi is enabled
if [[ "$(nmcli radio wifi)" == "disabled" ]]; then
    choice=$(echo -e "Yes\nNo" | fuzzel --dmenu --prompt "WiFi is disabled. Enable? " --width 20)
    if [[ "$choice" == "Yes" ]]; then
        nmcli radio wifi on
        notify "WiFi enabled, scanning..."
        sleep 2
    else
        exit 0
    fi
fi

# 2. Get the list of APs
wifi_list=$(nmcli -t -f "ACTIVE,SSID,SECURITY,SIGNAL" device wifi list | awk -F: '
    $2 != "" {
        prefix = ($1 == "yes") ? "󰄬 " : "  "
        sec = ($3 ~ /WPA|WEP/) ? "" : ""
        printf "%s %-25s  %s  %3s%%\n", prefix, $2, sec, $4
    }' | sort -u -t' ' -k2,2)

if [[ -z "$wifi_list" ]]; then
    notify "No networks found"
    exit 1
fi

# 3. Show menu
chosen=$(echo -e "$wifi_list\n󰖪 Disconnect\n󰤨 Rescan" | fuzzel $FUZZEL_OPTS)

[[ -z "$chosen" ]] && exit 0

# 4. Handle Special Options
if [[ "$chosen" == *"Disconnect"* ]]; then
    device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2=="wifi" && $3=="connected" {print $1; exit}')
    if [[ -n "$device" ]]; then
        nmcli device disconnect "$device"
        notify "Disconnected"
    fi
    exit 0
elif [[ "$chosen" == *"Rescan"* ]]; then
    notify "Rescanning..."
    nmcli device wifi rescan
    sleep 2
    exec "$0"
    exit 0
fi

# 5. Extract SSID
# Remove the first 3 chars (icon + space) and then everything after the double spaces
ssid=$(echo "$chosen" | sed 's/^...//' | sed 's/  .*//' | sed 's/[[:space:]]*$//')

# 6. Attempt Connection
if nmcli connection show --active | grep -q "$ssid"; then
    notify "Already connected to $ssid"
    exit 0
fi

if nmcli connection show | grep -q "$ssid"; then
    notify "Connecting to saved: $ssid"
    if nmcli connection up "$ssid"; then
        notify "Connected to $ssid"
    else
        notify "Failed to connect"
    fi
else
    if [[ "$chosen" == *""* ]]; then
        password=$(fuzzel --dmenu --password --prompt "Password for $ssid: " --width 45)
        [[ -z "$password" ]] && exit 0
        if nmcli device wifi connect "$ssid" password "$password"; then
            notify "Connected to $ssid"
        else
            notify "Connection failed"
        fi
    else
        if nmcli device wifi connect "$ssid"; then
            notify "Connected to $ssid"
        else
            notify "Connection failed"
        fi
    fi
fi
