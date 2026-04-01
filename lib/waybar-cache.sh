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
# Dependencies: jq (optional), flock
# Author: groot
# Modified: 2026-04-01

# lib/waybar-cache.sh
# Purpose: Shared caching utility for Waybar status scripts
# Usage: source "$(dirname "$0")/lib/waybar-cache.sh"
# Author: Custom
# Modified: 2026-04-01

set -euo pipefail

# Cache configuration
CACHE_DIR="${WAYBAR_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/waybar}"
CACHE_STALE_THRESHOLD="${WAYBAR_STALE_THRESHOLD:-300}"  # Default 5 minutes
CACHE_DEBUG="${WAYBAR_CACHE_DEBUG:-0}"  # Set to 1 to enable debug logging
CACHE_DEBUG_LOG="${CACHE_DIR}/debug.log"

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# ===== Helper Functions =====

cache_debug_log() {
    local msg="$1"
    if [[ "$CACHE_DEBUG" == "1" ]]; then
        printf '[%s] %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$msg" >> "$CACHE_DEBUG_LOG"
    fi
}

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
    
    cache_debug_log "cache_update_with_lock: Starting update for '$name'"
    
    local fd
    fd=$(cache_lock_acquire "$name") || {
        cache_debug_log "cache_update_with_lock: Failed to acquire lock for '$name'"
        return 1
    }
    
    # Execute command and capture output
    local output
    if output=$($cmd 2>/dev/null); then
        if [[ -n "$output" ]]; then
            cache_write "$name" "$output"
            cache_debug_log "cache_update_with_lock: Successfully updated '$name' (${#output} bytes)"
        else
            cache_debug_log "cache_update_with_lock: Command returned empty output for '$name'"
        fi
    else
        cache_debug_log "cache_update_with_lock: Command failed for '$name'"
    fi
    
    cache_lock_release "$fd"
}

cache_update_background() {
     local name="$1"
     local cmd="$2"
     
     # Spawn background process properly detached from parent
     {
         source "${WAYBAR_CACHE_LIB:-/home/groot/projects/scripts/lib/waybar-cache.sh}"
         cache_update_with_lock "$name" "$cmd"
         cache_debug_log "cache_update_background: Background update completed for '$name'"
     } &>/dev/null &
     
     disown 2>/dev/null || true
}

# ===== Stale Indicator Functions =====

cache_add_stale_indicator() {
    local json="$1"
    local age_seconds="${2:-0}"
    
    # Validate input is non-empty and valid JSON before transforming
    if [[ -z "$json" ]]; then
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "$json"
        return
    fi
    
    # Validate JSON before piping to jq -- return original if invalid
    if ! echo "$json" | jq -e . >/dev/null 2>&1; then
        cache_debug_log "cache_add_stale_indicator: invalid JSON input, passing through"
        echo "$json"
        return 1
    fi
    
    local age_str
    age_str=$(cache_get_age_string "$age_seconds")
    
    # Add stale indicators
    local result
    if result=$(echo "$json" | jq -c \
        --arg age_str "$age_str" \
        '.class |= (. // "") + " stale" | 
         .tooltip |= (. // "") + "\n⚠ Cached data (\($age_str))"' 2>/dev/null); then
        echo "$result"
    else
        # jq transform failed, return original
        cache_debug_log "cache_add_stale_indicator: jq transform failed, returning original"
        echo "$json"
    fi
}

# ===== Waybar Output Helpers =====

waybar_output() {
    local text="$1"
    local tooltip="${2:-}"
    local class="${3:-}"
    
    if ! command -v jq &> /dev/null; then
        # Fallback without jq -- manually escape characters that break JSON:
        # backslashes first, then double quotes, then newlines, then tabs
        local escaped_text escaped_tooltip escaped_class
        escaped_text="${text//\\/\\\\}"
        escaped_text="${escaped_text//\"/\\\"}"
        escaped_text="${escaped_text//$'\n'/\\n}"
        escaped_text="${escaped_text//$'\t'/\\t}"
        escaped_tooltip="${tooltip//\\/\\\\}"
        escaped_tooltip="${escaped_tooltip//\"/\\\"}"
        escaped_tooltip="${escaped_tooltip//$'\n'/\\n}"
        escaped_tooltip="${escaped_tooltip//$'\t'/\\t}"
        escaped_class="${class//\\/\\\\}"
        escaped_class="${escaped_class//\"/\\\"}"
        escaped_class="${escaped_class//$'\n'/\\n}"
        escaped_class="${escaped_class//$'\t'/\\t}"
        printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$escaped_text" "$escaped_tooltip" "$escaped_class"
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
    local default_output="${4:-}"
    local script="${5:-}"
    
    cache_debug_log "cache_serve: Serving cache for '$name'"
    
    if [[ ! -f "${CACHE_DIR}/${name}.json" ]]; then
        # No cache exists, trigger background update
        cache_debug_log "cache_serve: No cache file found for '$name', triggering background update"
        cache_update_background "$name" "$cmd" "$script"
        
        # Return default output if provided, otherwise fail
        if [[ -n "$default_output" ]]; then
            echo "$default_output"
            return 0
        else
            return 1
        fi
    fi
    
    local cached
    if ! cached=$(cache_read "$name"); then
        # Cache exists but is invalid
        cache_debug_log "cache_serve: Cache file invalid for '$name', triggering background update"
        cache_update_background "$name" "$cmd" "$script"
        
        # Return default output if provided, otherwise fail
        if [[ -n "$default_output" ]]; then
            echo "$default_output"
            return 0
        else
            return 1
        fi
    fi
    
    # Check if cache is stale
    if cache_is_stale "${CACHE_DIR}/${name}.json" "$threshold"; then
        # Cache is stale, mark for background update
        cache_debug_log "cache_serve: Cache stale for '$name', triggering background update"
        cache_update_background "$name" "$cmd" "$script"
        
         # Add stale indicator to output and echo it
         local age
         age=$(cache_get_file_age "${CACHE_DIR}/${name}.json")
         cache_add_stale_indicator "$cached" "$age"
    else
        # Cache is fresh
        cache_debug_log "cache_serve: Serving fresh cache for '$name'"
        echo "$cached"
    fi
}

# Export functions
export -f cache_debug_log
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
export -f cache_update_background
export -f cache_add_stale_indicator
export -f waybar_output
export -f cache_serve
