#!/bin/bash

# Waybar script for git repository status

# Get the JSON data from repostatus
json_data=$(/home/groot/projects/scripts/repostatus --json-summary)

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "{"text": "Error: jq is not installed", "class": "error"}"
    exit 1
fi

# Parse the JSON data
overall_status=$(echo "$json_data" | jq -r '.overall_status')
status_counts=$(echo "$json_data" | jq '.status_counts')
repos=$(echo "$json_data" | jq -c '.repos[]')

# Set the class based on the overall status
class="$overall_status"

# Calculate the counts for the four-light system
good_count=$(echo "$status_counts" | jq -r '.clean // 0')
dirty_count=$(( $(echo "$status_counts" | jq -r '.dirty // 0') + $(echo "$status_counts" | jq -r '.ahead // 0') ))
bad_count=$(( $(echo "$status_counts" | jq -r '.behind // 0') + $(echo "$status_counts" | jq -r '.diverged // 0') ))
uninitialized_count=$(echo "$status_counts" | jq -r '.uninitialized // 0')

# Define colors
green_color="#a6e3a1"
yellow_color="#f9e2af"
red_color="#f38ba8"
grey_color="#6c7086" # Catppuccin "subtext0"

# Build the text for Waybar using Pango markup
text="<span color='$green_color'></span> $good_count <span color='$yellow_color'></span> $dirty_count <span color='$red_color'></span> $bad_count <span color='$grey_color'></span> $uninitialized_count"

# Build the tooltip
tooltip=""
if [ -n "$repos" ]; then
    while IFS= read -r repo; do
        name=$(echo "$repo" | jq -r '.name')
        status=$(echo "$repo" | jq -r '.status')
        tooltip="$tooltip$name: $status\n"
    done <<< "$repos"
fi

if [ -z "$tooltip" ]; then
    tooltip="All repositories are clean."
fi

# Output the JSON for Waybar
printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$text" "$class" "$tooltip"
