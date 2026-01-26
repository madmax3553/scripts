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
# Script: waybar-cache.sh
# Purpose: Shared caching utility for Waybar status scripts
# Dependencies: <fill in as needed>
# Author: Custom
# Modified: 2026-01-24

# lib/waybar-cache.sh
# Purpose: Shared caching utility for Waybar status scripts
# Usage: source "$(dirname "$0")/lib/waybar-cache.sh"
# Author: Custom
# Modified: 2026-01-24

set -euo pipefail

# Cache configuration
CACHE_DIR="${WAYBAR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar}"
CACHE_STALE_THRESHOLD="${WAYBAR_STALE_THRESHOLD:-300}"  # Default 5 minutes

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# ===== Helper Functions =====

cache_get_age_string() {
    local seconds="$1"
    if (( seconds < 60 )); then
        echo "${seconds}s ago"
    elif (( seconds < 3600 )); then
        echo "$((seconds / 60))m ago"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m ago"
    fi
}

cache_get_file_age() {
    local file="$1"
    local mtime
    mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    echo $(($(date +%s) - mtime))
}

cache_is_stale() {
    local file="$1"
    local threshold="${2:-$CACHE_STALE_THRESHOLD}"
    
    if [[ ! -f "$file" ]]; then
        return 0  # File doesn't exist, consider it stale
    fi
    
    local age
    age=$(cache_get_file_age "$file")
    (( age > threshold ))
}

cache_is_valid() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        # Without jq, just check if file exists and has content
        [[ -s "$file" ]]
        return
    fi
    
    # With jq, validate JSON
    jq -e . "$file" >/dev/null 2>&1
}

# ===== Cache Read/Write Functions =====

cache_read() {
    local name="$1"
    local file="${CACHE_DIR}/${name}.json"
    
    if cache_is_valid "$file"; then
        cat "$file"
    else
        return 1
    fi
}

cache_write() {
    local name="$1"
    local content="$2"
    local file="${CACHE_DIR}/${name}.json"
    
    # Atomic write with temp file
    local tmp_file="${file}.tmp.$$"
    echo "$content" > "$tmp_file"
    mv "$tmp_file" "$file"
}

cache_clear() {
    local name="$1"
    local file="${CACHE_DIR}/${name}.json"
    rm -f "$file"
}

cache_lock_acquire() {
    local name="$1"
    local lock_file="${CACHE_DIR}/${name}.lock"
    local fd=200
    
    # Open file descriptor (200 is arbitrary, just needs to be >3)
    eval "exec $fd>'$lock_file'"
    
    # Try to acquire non-blocking lock
    if flock -n "$fd" 2>/dev/null; then
        echo "$fd"
        return 0
    else
        eval "exec $fd>&-"
        return 1
    fi
}

cache_lock_release() {
    local fd="$1"
    if [[ -n "$fd" && "$fd" -gt 2 ]]; then
        flock -u "$fd" 2>/dev/null || true
        eval "exec $fd>&-" 2>/dev/null || true
    fi
}

cache_update_with_lock() {
    local name="$1"
    local cmd="$2"
    
    local fd
    fd=$(cache_lock_acquire "$name") || return 1
    
    # Execute command and capture output
    local output
    if output=$($cmd 2>/dev/null); then
        if [[ -n "$output" ]]; then
            cache_write "$name" "$output"
        fi
    fi
    
    cache_lock_release "$fd"
}

# ===== Stale Indicator Functions =====

cache_add_stale_indicator() {
    local json="$1"
    local age_seconds="${2:-0}"
    
    if ! command -v jq &> /dev/null; then
        echo "$json"
        return
    fi
    
    local age_str
    age_str=$(cache_get_age_string "$age_seconds")
    
    # Add stale indicators
    echo "$json" | jq -c \
        --arg age_str "$age_str" \
        '.class |= (. // "") + " stale" | 
         .tooltip |= (. // "") + "\n⚠ Cached data (\($age_str))"'
}

# ===== Waybar Output Helpers =====

waybar_output() {
    local text="$1"
    local tooltip="${2:-}"
    local class="${3:-}"
    
    if ! command -v jq &> /dev/null; then
        # Fallback without jq
        printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$class"
        return
    fi
    
    jq -nc \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

# ===== Main Cache Logic =====

cache_serve() {
    local name="$1"
    local cmd="$2"
    local threshold="${3:-$CACHE_STALE_THRESHOLD}"
    
    if [[ ! -f "${CACHE_DIR}/${name}.json" ]]; then
        # No cache exists, trigger background update
        cache_update_with_lock "$name" "$cmd" &
        return 1
    fi
    
    local cached
    if ! cached=$(cache_read "$name"); then
        # Cache exists but is invalid
        cache_update_with_lock "$name" "$cmd" &
        return 1
    fi
    
    # Check if cache is stale
    if cache_is_stale "${CACHE_DIR}/${name}.json" "$threshold"; then
        # Cache is stale, mark for background update
        cache_update_with_lock "$name" "$cmd" &
        
        # Add stale indicator to output
        local age
        age=$(cache_get_file_age "${CACHE_DIR}/${name}.json")
        cache_add_stale_indicator "$cached" "$age"
    else
        # Cache is fresh
        echo "$cached"
    fi
}

# Export functions
export -f cache_get_age_string
export -f cache_get_file_age
export -f cache_is_stale
export -f cache_is_valid
export -f cache_read
export -f cache_write
export -f cache_clear
export -f cache_lock_acquire
export -f cache_lock_release
export -f cache_update_with_lock
export -f cache_add_stale_indicator
export -f waybar_output
export -f cache_serve
