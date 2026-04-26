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
# Script: waybar-journal.sh
# Purpose: Output master TODO count and tooltip for waybar journal module
# Dependencies: awk, jq
# Author: groot
# Created: 2026-02-11

TODO_FILE="${JOURNAL_DIR:-${HOME}/projects/journal}/TODO.md"

if [[ ! -f "${TODO_FILE}" ]]; then
    jq -cn --arg text "󰈙 0" --arg tooltip "TODO.md not found: ${TODO_FILE}" \
        '{text: $text, tooltip: $tooltip, class: "missing"}'
    exit 0
fi

mapfile -t todo_lines < <(awk '
    function emit_section(name) {
        if (counts[name] > 0) {
            print ""
            print name " (" counts[name] ")"
            printf "%s", items[name]
        }
    }

    /^## Completed$/ { exit }
    /^## High Priority$/ { section = "High Priority"; next }
    /^## Medium Priority$/ { section = "Medium Priority"; next }
    /^## Low Priority$/ { section = "Low Priority"; next }
    /^## / { section = ""; next }

    section != "" && /^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\]/ {
        item = $0
        sub(/^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\][[:space:]]*/, "", item)
        counts[section]++
        total++
        items[section] = items[section] "- " item "\n"
    }

    END {
        print total + 0
        if (total == 0) {
            print "No open TODOs"
            exit
        }

        print "Open TODOs: " total
        emit_section("High Priority")
        emit_section("Medium Priority")
        emit_section("Low Priority")
        print ""
        print "Click to open TODO.md"
    }
' "${TODO_FILE}" 2>/dev/null)

count="${todo_lines[0]:-0}"
tooltip="$(printf '%s\n' "${todo_lines[@]:1}")"
class="clear"
if (( count > 0 )); then
    class="has-todos"
fi

jq -cn --arg text "󰈙 ${count}" --arg tooltip "${tooltip}" --arg class "${class}" \
    '{text: $text, tooltip: $tooltip, class: $class}'
