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
# Script: tmux-dashboard-control.sh
# Purpose: Launch, surface, reload, or menu the tmux dashboard
# Dependencies: tmux, ghostty, hyprctl, jq, fuzzel/rofi
# Author: groot
# Modified: 2026-03-14

set -euo pipefail

source "/home/groot/projects/scripts/lib/common.sh"

TITLE="Dashboard"
SESSION_NAME="${TMUX_DASHBOARD_SESSION:-dashboard}"
DASHBOARD_CMD="/home/groot/.local/bin/tmux-dashboard"

find_dashboard_window() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1

    hyprctl -j clients | jq -r --arg title "$TITLE" '
        map(select((.title // "") == $title or (.initialTitle // "") == $title)) |
        max_by(.focusHistoryID // 0) | .address // empty
    '
}

focus_dashboard_window() {
    local address="${1:-}"
    [[ -z "$address" ]] && return 1
    hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1
}

close_dashboard_window() {
    local address="${1:-}"
    [[ -z "$address" ]] && return 0
    hyprctl dispatch closewindow "address:${address}" >/dev/null 2>&1 || true
}

wait_for_window_close() {
    local address="${1:-}"
    local attempt
    [[ -z "$address" ]] && return 0

    for attempt in {1..20}; do
        if [[ -z "$(find_dashboard_window || true)" ]]; then
            return 0
        fi
        sleep 0.1
    done

    return 1
}

launch_dashboard_window() {
    setsid ghostty --title="$TITLE" --window-width=180 --window-height=52 -e "$DASHBOARD_CMD" >/dev/null 2>&1 &
}

load_dashboard() {
    if [[ -n "$(find_dashboard_window)" ]]; then
        return 0
    fi
    launch_dashboard_window
}

surface_dashboard() {
    local address=""
    address="$(find_dashboard_window || true)"
    if [[ -n "$address" ]]; then
        focus_dashboard_window "$address"
        return 0
    fi
    load_dashboard
}

reload_dashboard() {
    local address=""
    address="$(find_dashboard_window || true)"
    close_dashboard_window "$address"
    wait_for_window_close "$address" || true
    tmux kill-session -t "$SESSION_NAME" >/dev/null 2>&1 || true
    launch_dashboard_window
}

show_menu() {
    local choice=""

    if command -v fuzzel >/dev/null 2>&1; then
        choice="$(printf '%s\n' 'Surface dashboard' 'Reload dashboard' 'Load dashboard' | fuzzel --dmenu --prompt 'Dashboard ' --lines 6 || true)"
    elif command -v rofi >/dev/null 2>&1; then
        choice="$(printf '%s\n' 'Surface dashboard' 'Reload dashboard' 'Load dashboard' | rofi -dmenu -p 'Dashboard' || true)"
    else
        die "Need fuzzel or rofi for dashboard menu"
    fi

    case "$choice" in
        'Surface dashboard') surface_dashboard ;;
        'Reload dashboard') reload_dashboard ;;
        'Load dashboard') load_dashboard ;;
        *) return 0 ;;
    esac
}

case "${1:-surface}" in
    load)
        load_dashboard
        ;;
    surface)
        surface_dashboard
        ;;
    reload)
        reload_dashboard
        ;;
    menu)
        show_menu
        ;;
    *)
        die "Usage: $(basename "$0") [load|surface|reload|menu]"
        ;;
esac
