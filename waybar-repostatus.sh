#!/bin/bash

# Waybar script for git repository status with caching
# Returns cached data immediately, updates in background

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar"
CACHE_FILE="$CACHE_DIR/repostatus.json"
LOCK_FILE="$CACHE_DIR/repostatus.lock"
STALE_THRESHOLD=300  # Consider cache stale after 5 minutes
mkdir -p "$CACHE_DIR"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo '{"text": "Error: jq not installed", "class": "error"}'
    exit 1
fi

# Default fallback when no cache exists
DEFAULT_OUTPUT='{"text": "⏳ Loading...", "class": "loading", "tooltip": "Scanning repositories..."}'

# Function to get human-readable age
get_age_string() {
    local seconds="$1"
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s ago"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m ago"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m ago"
    fi
}

# Function to generate waybar output from repostatus JSON
generate_output() {
    local json_data="$1"
    local is_stale="${2:-false}"
    local cache_age="$3"
    
    # Parse the JSON data
    local overall_status status_counts repos
    overall_status=$(echo "$json_data" | jq -r '.overall_status // "unknown"')
    status_counts=$(echo "$json_data" | jq '.status_counts // {}')
    repos=$(echo "$json_data" | jq -c '.repos[]?' 2>/dev/null)

    # Set the class based on the overall status
    local class="$overall_status"
    if [ "$is_stale" = "true" ]; then
        class="$class stale"
    fi

    # Calculate the counts for the four-light system
    local good_count dirty_count bad_count uninitialized_count
    good_count=$(echo "$status_counts" | jq -r '.clean // 0')
    dirty_count=$(( $(echo "$status_counts" | jq -r '.dirty // 0') + $(echo "$status_counts" | jq -r '.ahead // 0') ))
    bad_count=$(( $(echo "$status_counts" | jq -r '.behind // 0') + $(echo "$status_counts" | jq -r '.diverged // 0') ))
    uninitialized_count=$(echo "$status_counts" | jq -r '.uninitialized // 0')

    # Define colors
    local green_color="#a6e3a1"
    local yellow_color="#f9e2af"
    local red_color="#f38ba8"
    local grey_color="#6c7086"
    local stale_color="#585b70"

    # Build the text for Waybar using Pango markup with simple filled circles
    local text="<span foreground='$green_color'>●</span> $good_count <span foreground='$yellow_color'>●</span> $dirty_count <span foreground='$red_color'>●</span> $bad_count <span foreground='$grey_color'>●</span> $uninitialized_count"
    
    # Add stale indicator if cached
    if [ "$is_stale" = "true" ]; then
        text="<span foreground='$stale_color'>◐</span> $text"
    fi

    # Build the tooltip
    local tooltip=""
    if [ -n "$repos" ]; then
        while IFS= read -r repo; do
            local name status
            name=$(echo "$repo" | jq -r '.name')
            status=$(echo "$repo" | jq -r '.status')
            tooltip="$tooltip$name: $status\n"
        done <<< "$repos"
    fi

    if [ -z "$tooltip" ]; then
        tooltip="All repositories are clean."
    fi
    
    # Add cache age to tooltip if stale
    if [ "$is_stale" = "true" ] && [ -n "$cache_age" ]; then
        local age_str
        age_str=$(get_age_string "$cache_age")
        tooltip="$tooltip\n⚠ Cached data ($age_str)"
    fi

    # Output the JSON for Waybar
    printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$text" "$class" "$tooltip"
}

# Function to update cache in background
update_cache() {
    # Use lock to prevent multiple simultaneous updates
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        # Another update is already running
        return
    fi

    # Get fresh data from repostatus
    local json_data
    json_data=$(repostatus --json-summary 2>/dev/null)
    
    if [ -n "$json_data" ] && echo "$json_data" | jq -e . >/dev/null 2>&1; then
        # Valid JSON received, generate output and cache it (not stale)
        local output
        output=$(generate_output "$json_data" "false" "")
        echo "$output" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    fi
    
    flock -u 200
}

# Main logic: return cache immediately, update in background

# If cache exists and is valid, output it
if [ -f "$CACHE_FILE" ]; then
    cached=$(cat "$CACHE_FILE")
    if [ -n "$cached" ] && echo "$cached" | jq -e . >/dev/null 2>&1; then
        # Check cache age
        cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        now=$(date +%s)
        cache_age=$((now - cache_mtime))
        
        if [ "$cache_age" -gt "$STALE_THRESHOLD" ]; then
            # Cache is stale, modify output to show stale indicator
            # Re-parse and regenerate with stale flag
            # Extract original data from cached output and mark as stale
            text=$(echo "$cached" | jq -r '.text')
            tooltip=$(echo "$cached" | jq -r '.tooltip')
            class=$(echo "$cached" | jq -r '.class')
            
            # Add stale indicator to text if not already present
            stale_color="#585b70"
            age_str=$(get_age_string "$cache_age")
            
            if [[ "$text" != *"◐"* ]]; then
                text="<span foreground='$stale_color'>◐</span> $text"
            fi
            
            # Add stale class if not present
            if [[ "$class" != *"stale"* ]]; then
                class="$class stale"
            fi
            
            # Add age to tooltip if not present
            if [[ "$tooltip" != *"Cached data"* ]]; then
                tooltip="$tooltip\n⚠ Cached data ($age_str)"
            else
                # Update the age in existing tooltip
                tooltip=$(echo "$tooltip" | sed "s/Cached data ([^)]*)/Cached data ($age_str)/")
            fi
            
            printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$text" "$class" "$tooltip"
        else
            # Cache is fresh
            echo "$cached"
        fi
    else
        echo "$DEFAULT_OUTPUT"
    fi
else
    echo "$DEFAULT_OUTPUT"
fi

# Update cache in background (don't wait for it)
update_cache &
