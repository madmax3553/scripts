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
# Script: status-cache-daemon.sh
# Purpose: Dedicated cache writer for repo status and system updates
# Dependencies: jq, flock, repostatus, yay/checkupdates
# Author: groot
# Modified: 2026-03-20

set -euo pipefail

source "/home/groot/projects/scripts/lib/waybar-cache.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

REPOS_CACHE="repos-data"
UPDATES_CACHE="updates-data"
REPOS_INTERVAL="${STATUS_REPOS_INTERVAL:-300}"      # 5 minutes
UPDATES_INTERVAL="${STATUS_UPDATES_INTERVAL:-1800}"  # 30 minutes
PID_FILE="${CACHE_DIR}/status-daemon.pid"

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  start         Start the daemon (default, runs in foreground)
  stop          Stop a running daemon
  refresh-repos Force immediate repo status refresh
  refresh-updates Force immediate updates refresh
  refresh-all   Force immediate refresh of everything
  status        Show daemon status
  -h, --help    Show this help

Environment:
  STATUS_REPOS_INTERVAL     Repo refresh interval in seconds (default: 300)
  STATUS_UPDATES_INTERVAL   Update refresh interval in seconds (default: 1800)
EOF
}

generate_repos_data() {
    # Call repostatus --json-summary and pass through the raw JSON
    # This is the canonical raw data format that all consumers read
    local json_data
    json_data=$(repostatus --json-summary 2>/dev/null) || return 1
    [[ -z "$json_data" ]] && return 1

    # Validate JSON before writing
    if command -v jq &>/dev/null; then
        echo "$json_data" | jq -c '.' 2>/dev/null || return 1
    else
        echo "$json_data"
    fi
}

generate_updates_data() {
    # Try checkupdates first, then yay, then pacman
    local updates_output=""
    local ignored_packages=""
    local ignore_file="$HOME/.config/yay/ignored_packages"
    local total=0

    # Load ignored packages if file exists
    if [[ -f "$ignore_file" && -s "$ignore_file" ]]; then
        ignored_packages=$(tr '\n' ',' < "$ignore_file" 2>/dev/null | sed 's/,$//')
    fi

    # Try commands in priority order
    if command -v checkupdates &>/dev/null; then
        updates_output=$(checkupdates 2>/dev/null || true)
    fi

    if [[ -z "$updates_output" ]] && command -v yay &>/dev/null; then
        if [[ -n "$ignored_packages" ]]; then
            updates_output=$(yay -Qu --ignore "$ignored_packages" 2>/dev/null || true)
        else
            updates_output=$(yay -Qu 2>/dev/null || true)
        fi
    fi

    if [[ -z "$updates_output" ]] && command -v pacman &>/dev/null; then
        updates_output=$(pacman -Qu 2>/dev/null || true)
    fi

    # Parse output into structured JSON
    # Format: "name old_version -> new_version"
    local packages="[]"

    if [[ -n "$updates_output" ]]; then
        total=$(echo "$updates_output" | grep -c . || true)
        packages=$(echo "$updates_output" | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local name version
            name=$(echo "$line" | awk '{print $1}')
            version=$(echo "$line" | cut -d' ' -f2-)
            jq -nc --arg name "$name" --arg version "$version" \
                '{name: $name, version: $version}'
        done | jq -sc '.')
    fi

    # Build the canonical raw data JSON
    local ignored_list="[]"
    if [[ -n "$ignored_packages" ]]; then
        ignored_list=$(echo "$ignored_packages" | tr ',' '\n' | jq -R '.' | jq -sc '.')
    fi

    jq -nc \
        --argjson total "$total" \
        --argjson packages "$packages" \
        --argjson ignored "$ignored_list" \
        '{total: $total, packages: $packages, ignored: $ignored}'
}

write_pid() {
    echo "$$" > "$PID_FILE"
}

cleanup_pid() {
    rm -f "$PID_FILE"
}

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

do_stop() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            echo "Stopped daemon (PID $pid)"
        else
            rm -f "$PID_FILE"
            echo "Daemon not running (stale PID file removed)"
        fi
    else
        echo "Daemon not running"
    fi
}

do_status() {
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        echo "Daemon running (PID $pid)"

        local repos_file="${CACHE_DIR}/${REPOS_CACHE}.json"
        local updates_file="${CACHE_DIR}/${UPDATES_CACHE}.json"

        if [[ -f "$repos_file" ]]; then
            local age
            age=$(cache_get_file_age "$repos_file")
            echo "  repos-data: $(cache_get_age_string "$age")"
        else
            echo "  repos-data: not cached"
        fi

        if [[ -f "$updates_file" ]]; then
            local age
            age=$(cache_get_file_age "$updates_file")
            echo "  updates-data: $(cache_get_age_string "$age")"
        else
            echo "  updates-data: not cached"
        fi
    else
        echo "Daemon not running"
    fi
}

refresh_repos() {
    cache_debug_log "status-daemon: refreshing repos data"
    cache_update_with_lock "$REPOS_CACHE" generate_repos_data
    # Also regenerate the waybar-formatted cache
    generate_repos_waybar
}

refresh_updates() {
    cache_debug_log "status-daemon: refreshing updates data"
    cache_update_with_lock "$UPDATES_CACHE" generate_updates_data
    # Also regenerate the waybar-formatted cache
    generate_updates_waybar
}

# ─────────────────────────────────────────────────────────────────────────────
# Waybar-formatted cache generators
# Read from raw data cache and produce waybar-compatible JSON
# ─────────────────────────────────────────────────────────────────────────────

generate_repos_waybar() {
    local raw
    raw=$(cache_read "$REPOS_CACHE" 2>/dev/null) || return 1
    [[ -z "$raw" ]] && return 1

    local overall_status status_counts
    overall_status=$(echo "$raw" | jq -r '.overall_status // "unknown"')
    status_counts=$(echo "$raw" | jq '.status_counts // {}')
    local repos
    repos=$(echo "$raw" | jq -c '.repos[]?' 2>/dev/null)

    local good_count dirty_count bad_count uninitialized_count
    good_count=$(echo "$status_counts" | jq -r '.clean // 0')
    dirty_count=$(( $(echo "$status_counts" | jq -r '.dirty // 0') + $(echo "$status_counts" | jq -r '.ahead // 0') ))
    bad_count=$(( $(echo "$status_counts" | jq -r '.behind // 0') + $(echo "$status_counts" | jq -r '.diverged // 0') ))
    uninitialized_count=$(echo "$status_counts" | jq -r '.uninitialized // 0')

    local green_color="#a6e3a1"
    local yellow_color="#f9e2af"
    local red_color="#f38ba8"
    local grey_color="#6c7086"

    local text="<span foreground='$green_color'>●</span> $good_count <span foreground='$yellow_color'>●</span> $dirty_count <span foreground='$red_color'>●</span> $bad_count <span foreground='$grey_color'>●</span> $uninitialized_count"

    local tooltip=""
    if [[ -n "$repos" ]]; then
        while IFS= read -r repo; do
            local name status
            name=$(echo "$repo" | jq -r '.name')
            status=$(echo "$repo" | jq -r '.status')
            tooltip+="$name: $status"$'\n'
        done <<< "$repos"
    fi
    tooltip="${tooltip%$'\n'}"
    [[ -z "$tooltip" ]] && tooltip="All repositories are clean."

    local waybar_json
    waybar_json=$(jq -nc \
        --arg text "$text" \
        --arg class "$overall_status" \
        --arg tooltip "$tooltip" \
        '{text: $text, class: $class, tooltip: $tooltip}')

    cache_write "repostatus" "$waybar_json"
}

generate_updates_waybar() {
    local raw
    raw=$(cache_read "$UPDATES_CACHE" 2>/dev/null) || return 1
    [[ -z "$raw" ]] && return 1

    local total ignored_list tooltip_text text
    total=$(echo "$raw" | jq -r '.total // 0')
    ignored_list=$(echo "$raw" | jq -r '.ignored[]? // empty' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

    if (( total > 0 )); then
        tooltip_text=$(echo "$raw" | jq -r '.packages[]? | "\(.name) \(.version)"' 2>/dev/null)
    else
        tooltip_text="No updates available"
    fi

    if [[ -n "$ignored_list" ]]; then
        tooltip_text="${tooltip_text}"$'\n'"Ignoring: ${ignored_list}"
    fi

    text="${total} updates"

    local waybar_json
    waybar_json=$(waybar_output "$text" "$tooltip_text" "")
    cache_write "yay-updates" "$waybar_json"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────

run_daemon() {
    if is_running; then
        echo "Daemon already running (PID $(cat "$PID_FILE"))" >&2
        exit 1
    fi

    write_pid
    trap cleanup_pid EXIT

    cache_debug_log "status-daemon: starting (PID $$)"
    cache_debug_log "status-daemon: repos interval=${REPOS_INTERVAL}s, updates interval=${UPDATES_INTERVAL}s"

    # Initial refresh on startup
    refresh_repos &
    refresh_updates &
    wait

    local last_repos last_updates now
    last_repos=$(date +%s)
    last_updates=$(date +%s)

    while true; do
        sleep 30  # Check every 30 seconds

        now=$(date +%s)

        if (( now - last_repos >= REPOS_INTERVAL )); then
            refresh_repos &
            last_repos="$now"
        fi

        if (( now - last_updates >= UPDATES_INTERVAL )); then
            refresh_updates &
            last_updates="$now"
        fi

        wait
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Command dispatch
# ─────────────────────────────────────────────────────────────────────────────

case "${1:-start}" in
    start)
        run_daemon
        ;;
    stop)
        do_stop
        ;;
    refresh-repos)
        refresh_repos
        ;;
    refresh-updates)
        refresh_updates
        ;;
    refresh-all)
        refresh_repos &
        refresh_updates &
        wait
        ;;
    status)
        do_status
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "Unknown command: $1" >&2
        usage >&2
        exit 1
        ;;
esac
