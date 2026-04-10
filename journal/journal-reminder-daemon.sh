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
# Script: journal-reminder-daemon.sh
# Purpose: Background daemon that sends periodic reminders to journal every 2 hours
# Dependencies: notify-send, hyprctl, grep, stat
# Author: groot
# Created: 2026-02-11

set -euo pipefail

source "/home/groot/projects/scripts/lib/colors.sh" 2>/dev/null || true

JOURNAL_DIR="${JOURNAL_DIR:-${HOME}/journal}"
DIARY_DIR="${JOURNAL_DIR}/diary"
TASK_REGISTRY="${JOURNAL_DIR}/tasks/active.md"
REMINDER_INTERVAL=7200
REMINDER_START_HOUR=7
REMINDER_END_HOUR=21
REMINDER_CHECK_INTERVAL=10
LOG_FILE="${HOME}/.local/state/journal-reminder.log"

log_message() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    printf '%s [%s] %s\n' "$(date +'%F %T')" "$$" "$*" >> "${LOG_FILE}"
}

get_active_task_count() {
    if [[ -f "${TASK_REGISTRY}" ]]; then
        grep -c "^Status: \[ \]4" "${TASK_REGISTRY}" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

should_send_reminder() {
    local current_hour
    current_hour=$(date +%H)

    if [[ $current_hour -lt $REMINDER_START_HOUR ]] || [[ $current_hour -ge $REMINDER_END_HOUR ]]; then
        return 1
    fi

    local today_file="${DIARY_DIR}/$(date +%Y-%m-%d).md"

    if [[ ! -f "$today_file" ]]; then
        return 0
    fi

    local file_mtime
    file_mtime=$(stat -c %Y "$today_file" 2>/dev/null || echo 0)

    local current_time
    current_time=$(date +%s)

    local time_diff=$((current_time - file_mtime))

    if [[ $time_diff -gt $REMINDER_INTERVAL ]]; then
        return 0
    else
        return 1
    fi
}

send_reminder() {
    local task_count
    task_count=$(get_active_task_count)

    local message
    if [[ $task_count -eq 0 ]]; then
        message="Time to journal! No active tasks."
    else
        message="Time to journal! You have $task_count active task$([ "$task_count" -ne 1 ] && echo 's')."
    fi

    log_message "Sending reminder: $message"

    notify-send \
        --app-name="Journal" \
        --urgency=critical \
        --expire-time=10000 \
        "📔 Journal Reminder" \
        "$message" \
        --action="open=Go to Journal" 2>/dev/null || true
}

on_reminder_click() {
    log_message "Reminder clicked - navigating to journal"

    hyprctl dispatch workspace 10 2>/dev/null || true
    sleep 0.1

    local today_file="${DIARY_DIR}/$(date +%Y-%m-%d).md"
    if [[ -f "$today_file" ]]; then
        notify-send --app-name="Journal" "Opening journal..." 2>/dev/null || true
    fi
}

main() {
    log_message "Journal reminder daemon starting..."
    log_message "Configuration: interval=${REMINDER_INTERVAL}s, window=${REMINDER_START_HOUR}:00-${REMINDER_END_HOUR}:00"

    local last_reminder_time=0

    while true; do
        local current_time
        current_time=$(date +%s)

        if should_send_reminder; then
            if [[ $((current_time - last_reminder_time)) -gt $((REMINDER_INTERVAL - 300)) ]]; then
                send_reminder
                last_reminder_time=$current_time
            fi
        fi

        sleep "$REMINDER_CHECK_INTERVAL"
    done
}

main "$@"
