#!/usr/bin/env bash
# Helper script: Generate repostatus output for waybar
# This is separated to avoid shell quoting issues in cache system

json_data=$(repostatus --json-summary 2>/dev/null) || exit 1
[[ -z "$json_data" ]] && exit 1

overall_status=$(echo "$json_data" | jq -r ".overall_status // \"unknown\"")
status_counts=$(echo "$json_data" | jq ".status_counts // {}")
repos=$(echo "$json_data" | jq -c ".repos[]?" 2>/dev/null)

good_count=$(echo "$status_counts" | jq -r ".clean // 0")
dirty_count=$(( $(echo "$status_counts" | jq -r ".dirty // 0") + $(echo "$status_counts" | jq -r ".ahead // 0") ))
bad_count=$(( $(echo "$status_counts" | jq -r ".behind // 0") + $(echo "$status_counts" | jq -r ".diverged // 0") ))
uninitialized_count=$(echo "$status_counts" | jq -r ".uninitialized // 0")

green_color="#a6e3a1"
yellow_color="#f9e2af"
red_color="#f38ba8"
grey_color="#6c7086"

text="<span foreground='$green_color'>●</span> $good_count <span foreground='$yellow_color'>●</span> $dirty_count <span foreground='$red_color'>●</span> $bad_count <span foreground='$grey_color'>●</span> $uninitialized_count"

tooltip=""
if [ -n "$repos" ]; then
    while IFS= read -r repo; do
        name=$(echo "$repo" | jq -r ".name")
        status=$(echo "$repo" | jq -r ".status")
        tooltip+="$name: $status"$'\n'
    done <<< "$repos"
fi

# Trim trailing newline
tooltip="${tooltip%$'\n'}"

if [ -z "$tooltip" ]; then
    tooltip="All repositories are clean."
fi

# Use jq to generate JSON output safely
jq -nc \
    --arg text "$text" \
    --arg class "$overall_status" \
    --arg tooltip "$tooltip" \
    '{text: $text, class: $class, tooltip: $tooltip}'
