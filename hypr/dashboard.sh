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
# Script: dashboard.sh
# Purpose: Launch, surface, reload, or menu the desktop dashboard
# Dependencies: dash-home-c, ghostty, hyprctl, jq, fuzzel or rofi
# Author: groot
# Modified: 2026-05-15

set -euo pipefail

source "/home/groot/projects/scripts/lib/common.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

DASHBOARD_TITLE="${DASHBOARD_TITLE:-Dashboard}"
DASHBOARD_CMD="${DASHBOARD_CMD:-/home/groot/projects/dash-home-c/dash-home-c}"
DASHBOARD_TERMINAL="${DASHBOARD_TERMINAL:-ghostty}"
DASHBOARD_WIDTH="${DASHBOARD_WIDTH:-180}"
DASHBOARD_HEIGHT="${DASHBOARD_HEIGHT:-52}"

# ─────────────────────────────────────────────────────────────────────────────
# Window Control
# ─────────────────────────────────────────────────────────────────────────────

find_dashboard_window() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1

    hyprctl -j clients 2>/dev/null | jq -r --arg title "$DASHBOARD_TITLE" '
        map(select((.title // "") == $title or (.initialTitle // "") == $title)) |
        max_by(.focusHistoryID // 0) | .address // empty
    ' 2>/dev/null
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
    require_command "$DASHBOARD_TERMINAL"
    [[ -x "$DASHBOARD_CMD" ]] || die "Dashboard command is not executable: $DASHBOARD_CMD"

    setsid "$DASHBOARD_TERMINAL" \
        --title="$DASHBOARD_TITLE" \
        --window-width="$DASHBOARD_WIDTH" \
        --window-height="$DASHBOARD_HEIGHT" \
        -e "$DASHBOARD_CMD" >/dev/null 2>&1 &
}

load_dashboard() {
    local address=""
    address="$(find_dashboard_window || true)"
    [[ -n "$address" ]] && return 0

    launch_dashboard_window
}

surface_dashboard() {
    local address=""
    address="$(find_dashboard_window || true)"
    if [[ -n "$address" ]]; then
        focus_dashboard_window "$address"
        return 0
    fi

    launch_dashboard_window
}

reload_dashboard() {
    local address=""
    address="$(find_dashboard_window || true)"
    close_dashboard_window "$address"
    wait_for_window_close "$address" || true
    launch_dashboard_window
}

show_menu() {
    local choice=""

    if command -v fuzzel >/dev/null 2>&1; then
        choice="$(
            printf '%s\n' 'Surface dashboard' 'Reload dashboard' 'Load dashboard' |
                fuzzel --dmenu --prompt 'Dashboard ' --lines 6 || true
        )"
    elif command -v rofi >/dev/null 2>&1; then
        choice="$(
            printf '%s\n' 'Surface dashboard' 'Reload dashboard' 'Load dashboard' |
                rofi -dmenu -p 'Dashboard' || true
        )"
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

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

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
