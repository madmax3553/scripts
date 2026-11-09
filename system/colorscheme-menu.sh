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
# Script: colorscheme-menu.sh
# Purpose: Manage colorscheme presets, syncing, and watch mode from a fuzzel menu
# Dependencies: fuzzel, notify-send, python3, xdg-open, ghostty or another terminal
# Author: groot
# Modified: 2026-06-05

set -euo pipefail

CONFIG_DIR="${HOME}/.config/colorscheme"
ACTIVE_FILE="${CONFIG_DIR}/cyberdream.json"
SYNC_SCRIPT="${CONFIG_DIR}/sync-colors.sh"
WATCH_SCRIPT="${CONFIG_DIR}/watch-colors.sh"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}"
PID_FILE="${STATE_DIR}/colorscheme-watch.pid"
LOG_FILE="${STATE_DIR}/colorscheme-watch.log"
TERMINAL="${TERMINAL:-ghostty}"

menu_pick() {
    fuzzel --dmenu \
        --prompt "$1" \
        --width 34 \
        --lines 8 \
        --border-radius 12 \
        --border-width 2
}

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="Colorscheme" "$1" "$2" >/dev/null 2>&1 || true
    fi
}

require_tools() {
    local missing=0
    local tool

    for tool in fuzzel "$SYNC_SCRIPT" "$WATCH_SCRIPT"; do
        if [[ "$tool" == */* ]]; then
            [[ -x "$tool" ]] || missing=1
        else
            command -v "$tool" >/dev/null 2>&1 || missing=1
        fi
    done

    if ((missing == 1)); then
        notify "Colorscheme" "Missing required tools/scripts"
        exit 1
    fi
}

json_get() {
    local file="$1"
    local key="$2"

    python3 -c 'import json,sys
f=sys.argv[1]
k=sys.argv[2]
data=json.load(open(f))
cur=data
for part in k.split("."):
    cur=cur.get(part,"") if isinstance(cur,dict) else ""
print(cur if cur is not None else "")' "$file" "$key" 2>/dev/null || true
}

active_prompt() {
    local name accent

    name="$(json_get "$ACTIVE_FILE" "name")"
    accent="$(json_get "$ACTIVE_FILE" "colors.blue")"
    [[ -z "$name" ]] && name="cyberdream"
    [[ -z "$accent" ]] && accent="#5ea1ff"
    printf '󰸌 %s %s > ' "$name" "$accent"
}

watch_running() {
    [[ -f "$PID_FILE" ]] || return 1

    local pid
    pid="$(<"$PID_FILE")"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    rm -f "$PID_FILE"
    return 1
}

start_watch() {
    mkdir -p "$STATE_DIR"
    nohup "$WATCH_SCRIPT" >>"$LOG_FILE" 2>&1 &
    echo "$!" > "$PID_FILE"
    notify "Colorscheme" "Watch started"
}

stop_watch() {
    local pid

    pid="$(<"$PID_FILE")"
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    notify "Colorscheme" "Watch stopped"
}

pick_preset() {
    shopt -s nullglob
    local files=("$CONFIG_DIR"/*.json)
    shopt -u nullglob

    local presets=()
    local file
    local choice

    for file in "${files[@]}"; do
        presets+=("$(basename "$file")")
    done

    if [[ ${#presets[@]} -eq 0 ]]; then
        notify "Colorscheme" "No presets found in $CONFIG_DIR"
        return 0
    fi

    choice="$(printf '%s\n' "${presets[@]}" | menu_pick "󰉦 Preset > ")"
    [[ -z "$choice" ]] && return 0

    cp "$CONFIG_DIR/$choice" "$ACTIVE_FILE"
    "$SYNC_SCRIPT" >/dev/null 2>&1
    notify "Colorscheme" "Applied preset: $choice"
}

open_editor() {
    setsid "$TERMINAL" -e "${EDITOR:-nvim}" "$ACTIVE_FILE" >/dev/null 2>&1 &
}

main() {
    require_tools

    local watch_label watch_icon prompt choice
    if watch_running; then
        watch_label="Watch: stop"
        watch_icon=""
    else
        watch_label="Watch: start"
        watch_icon=""
    fi

    prompt="$(active_prompt)"

    local entry_sync="󰑓  Sync now"
    local entry_watch="${watch_icon}  ${watch_label}"
    local entry_edit="󰏫  Edit palette"
    local entry_preset="󰉦  Pick preset"
    local entry_open="  Open colors directory"
    local entry_quit="󰗼  Quit"

    choice="$(
        printf '%s\n' \
            "$entry_sync" \
            "$entry_watch" \
            "$entry_edit" \
            "$entry_preset" \
            "$entry_open" \
            "$entry_quit" |
            menu_pick "$prompt"
    )"

    case "$choice" in
        "$entry_sync")
            "$SYNC_SCRIPT" >/dev/null 2>&1
            notify "Colorscheme" "Colors synced"
            ;;
        "$entry_watch")
            if watch_running; then
                stop_watch
            else
                start_watch
            fi
            ;;
        "$entry_edit")
            open_editor
            ;;
        "$entry_preset")
            pick_preset
            ;;
        "$entry_open")
            xdg-open "$CONFIG_DIR" >/dev/null 2>&1 || true
            ;;
        *)
            exit 0
            ;;
    esac
}

main "$@"
