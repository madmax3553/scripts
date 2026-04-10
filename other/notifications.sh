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
# Script: notifications.sh
# Purpose: Waybar notification indicator (mako)
# Dependencies: makoctl
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

if ! command -v makoctl >/dev/null 2>&1; then
    waybar_output "notif" "makoctl not installed" "error"
    exit 0
fi

if makoctl mode | grep -q do-not-disturb; then
    waybar_output " DND" "Do Not Disturb On" "dnd"
    exit 0
fi

count=$(makoctl list | grep -c '^Notification')
if [ "$count" -eq 0 ]; then
    waybar_output " 0" "No Notifications" "no-notifs"
else
    waybar_output " $count" "$count Unread Notifications" "has-notifs"
fi
