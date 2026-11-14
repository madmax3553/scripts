#!/usr/bin/env bash
# Script: battery-fullcharge.sh
# Purpose: Confirm, then temporarily charge the battery to 100%
# Dependencies: fuzzel, notify-send, tlp, sudo
# Author: groot
# Modified: 2026-11-13

set -euo pipefail

notify() {
    local title="$1"
    local body="$2"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="Battery" "$title" "$body" >/dev/null 2>&1 || true
    fi
}

if ! command -v fuzzel >/dev/null 2>&1 || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    notify "Full charge" "No confirmation window available."
    exit 0
fi

if pgrep -x fuzzel >/dev/null 2>&1; then
    exit 0
fi

choice=$(
    printf '%s\n' "Yes" "No" |
        fuzzel --dmenu \
            --prompt "Charge to 100%? 45-55 returns on reboot. " \
            --width 52 \
            --lines 2
) || exit 0

[[ "$choice" == "Yes" ]] || exit 0

ac_online="0"
if [[ -r /sys/class/power_supply/AC/online ]]; then
    ac_online=$(cat /sys/class/power_supply/AC/online)
fi
if [[ "$ac_online" != "1" ]]; then
    notify "Full charge" "Plug in AC first."
    exit 0
fi

if sudo -n tlp fullcharge >/dev/null; then
    notify "Full charge" "Charging to 100%. The 45-55 band returns on the next reboot."
else
    notify "Full charge" "tlp fullcharge failed."
fi
