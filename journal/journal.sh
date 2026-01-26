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
# Script: journal.sh
# Purpose: Consolidated journal management with daily planning, TODO review, and window control
# Dependencies: nvim, jq, hyprctl (optional), ghostty/kitty/alacritty (optional)
# Author: Custom
# Modified: 2026-01-24

set -euo pipefail

# Source common libraries
source "/home/groot/projects/scripts/lib/colors.sh"
source "/home/groot/projects/scripts/lib/common.sh"

# ===== Configuration =====

JOURNAL_DIR="${JOURNAL_DIR:-${HOME}/journal}"
DIARY_DIR="${JOURNAL_DIR}/diary"
TODO_FILE="${JOURNAL_DIR}/TODO.md"
NOTES_DIR="${JOURNAL_DIR}/notes"
TERMINAL="${TERMINAL:-ghostty}"
TITLE_PREFIX="${TITLE_PREFIX:-Journal}"
LOG_FILE="${JOURNAL_LOG_FILE:-${XDG_STATE_HOME:-${HOME}/.local/state}/journal.log}"

# Today's info
TODAY="$(date +%Y-%m-%d)"
YESTERDAY="$(date -d "yesterday" +%Y-%m-%d)"
WEEKDAY="$(date +%u)"  # 1=Mon ... 7=Sun
IS_WEEKEND=$([[ "${WEEKDAY}" -ge 6 ]] && echo 1 || echo 0)
TITLE="${TITLE_PREFIX} ${TODAY}"
JOURNAL_FILE="${DIARY_DIR}/${TODAY}.md"

# State
JUMP_SECTION=""
FOUND_ADDR=""

# ===== Logging Functions =====

journal_log() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    printf '%s %s\n' "$(date +'%F %T')" "$*" >> "${LOG_FILE}"
}

# ===== Window Management Functions =====

focus_existing_window() {
    command -v hyprctl >/dev/null 2>&1 || return 1

    local address
    address="$(
        hyprctl -j clients 2>/dev/null | jq -r --arg title "${TITLE}" '
            map(select(
                (.title // "" ) == $title or
                (.initialTitle // "" ) == $title
            )) |
            max_by(.pid // 0) | .address // empty
        ' 2>/dev/null || echo ""
    )"

    if [[ -z "${address}" ]]; then
        journal_log "focus: no matching window found (title=${TITLE})"
        return 1
    fi

    FOUND_ADDR="${address}"
    journal_log "focus: focusing address ${address}"
    hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1 || journal_log "focus: dispatch failed"
    return 0
}

float_and_center() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    local hint_addr="${1:-}"

    local addr="${hint_addr}"
    if [[ -z "${addr}" ]]; then
        for _ in {1..25}; do
            addr="$(
                hyprctl -j clients 2>/dev/null | jq -r --arg title "${TITLE}" '
                    map(select(
                        (.title // "" ) == $title or
                        (.initialTitle // "" ) == $title
                    )) | max_by(.pid // 0) | .address // empty
                ' 2>/dev/null || echo ""
            )"
            [[ -n "${addr}" ]] && break
            sleep 0.08
        done
    fi

    if [[ -z "${addr}" ]]; then
        journal_log "float: no addr found for title ${TITLE}"
        return 0
    fi

    local floating
    floating="$(
        hyprctl -j clients 2>/dev/null | jq -r --arg addr "${addr}" '
            map(select(.address == $addr)) | .[0].floating // false
        ' 2>/dev/null || echo "false"
    )"

    hyprctl dispatch focuswindow "address:${addr}" >/dev/null 2>&1 || true
    if [[ "${floating}" != "true" ]]; then
        hyprctl dispatch togglefloating "address:${addr}" >/dev/null 2>&1 || true
        journal_log "float: toggled floating for ${addr}"
    fi
    hyprctl dispatch centerwindow "address:${addr}" >/dev/null 2>&1 || true
}

# ===== Template Creation Functions =====

create_template_weekday() {
    mkdir -p "${DIARY_DIR}"
    cat > "${JOURNAL_FILE}" <<'EOF'
# Daily Journal - %TODAY%

## Tasks Carried Over from Yesterday

## Morning
- 

## Goals for Today
- 

## Mid Day
- 

## After Lunch
- 

## Afternoon
- 

## Tasks Completed

## Learnings/Notes

## Reflection

## Tasks for Tomorrow
- 
EOF
    sed -i "s/%TODAY%/${TODAY}/" "${JOURNAL_FILE}"
}

create_template_weekend() {
    mkdir -p "${DIARY_DIR}"
    cat > "${JOURNAL_FILE}" <<'EOF'
# Weekend Journal - %TODAY%

## Tasks Carried Over from Yesterday

## This Weekend Intentions
- 

## Errands / Chores
- 

## Fun / Rest
- 

## Family / Friends
- 

## Gratitude

## Next Week Prep
- 
EOF
    sed -i "s/%TODAY%/${TODAY}/" "${JOURNAL_FILE}"
}

# ===== Daily Plan Functions =====

carry_forward_tasks() {
    local yesterday_file="${DIARY_DIR}/${YESTERDAY}.md"

    [[ ! -f "${yesterday_file}" ]] && return 0

    # Grab unchecked tasks and append under the carry-over section
    local tasks
    tasks="$(grep '^- \[ \]' "${yesterday_file}" || true)"
    [[ -z "${tasks}" ]] && return 0

    # Insert after the carry-over heading if not already present
    if ! grep -q "${tasks}" "${JOURNAL_FILE}"; then
        sed -i "/^## Tasks Carried Over from Yesterday/a ${tasks}" "${JOURNAL_FILE}"
    fi
}

ensure_today() {
    if [[ ! -f "${JOURNAL_FILE}" ]]; then
        journal_log "creating template: weekend=${IS_WEEKEND} file=${JOURNAL_FILE}"
        if [[ "${IS_WEEKEND}" -eq 1 ]]; then
            create_template_weekend
        else
            create_template_weekday
        fi
        carry_forward_tasks
        log_success "Created today's journal entry"
    else
        journal_log "journal exists: ${JOURNAL_FILE}"
    fi
}

pick_jump_section() {
    local hour
    hour="$(date +%H | sed 's/^0//')"

    if [[ "${IS_WEEKEND}" -eq 1 ]]; then
        if (( hour < 12 )); then
            JUMP_SECTION="This Weekend Intentions"
        elif (( hour < 16 )); then
            JUMP_SECTION="Fun / Rest"
        else
            JUMP_SECTION="Next Week Prep"
        fi
        journal_log "weekend jump -> ${JUMP_SECTION}"
        return
    fi

    if (( hour < 11 )); then
        JUMP_SECTION="Morning"
    elif (( hour < 14 )); then
        JUMP_SECTION="Mid Day"
    elif (( hour < 17 )); then
        JUMP_SECTION="Afternoon"
    else
        JUMP_SECTION="Tasks for Tomorrow"
    fi
    journal_log "weekday jump -> ${JUMP_SECTION}"
}

# ===== Launch Functions =====

launch_journal() {
    local cmd=()
    local nvim_cmds=("+set notitle")
    if [[ -n "${JUMP_SECTION}" ]]; then
        nvim_cmds+=("+silent!/^## ${JUMP_SECTION}")
    fi
    local nvim_full=(nvim "${nvim_cmds[@]}" "${JOURNAL_FILE}")
    journal_log "launch: terminal=${TERMINAL} title=\"${TITLE}\" jump=\"${JUMP_SECTION}\" file=${JOURNAL_FILE}"

    case "${TERMINAL}" in
        ghostty)
            cmd=(ghostty --title="${TITLE}" -e "${nvim_full[@]}")
            ;;
        kitty)
            cmd=(kitty --class Journal --title "${TITLE}" "${nvim_full[@]}")
            ;;
        alacritty)
            cmd=(alacritty --class Journal --title "${TITLE}" -e "${nvim_full[@]}")
            ;;
        *)
            cmd=("${TERMINAL}" -e "${nvim_full[@]}")
            ;;
    esac

    setsid "${cmd[@]}" >/dev/null 2>&1 &
    float_and_center "${FOUND_ADDR}"
}

# ===== Daily Plan Command =====

cmd_plan() {
    log_info "Generating daily plan..."
    ensure_today
    log_success "Daily plan ready at $JOURNAL_FILE"
}

# ===== Review TODOs Command =====

cmd_review() {
    log_info "Reviewing outstanding TODOs..."
    echo ""
    echo -e "${HEADER}=== Outstanding TODOs ===${RESET}"
    echo ""

    # Check main TODO file
    if [[ -f "${TODO_FILE}" ]]; then
        echo -e "${BOLD}📋 Main TODO List:${RESET}"
        grep -E '^\s*[-*]\s*\[[ ○◐●]\]' "${TODO_FILE}" 2>/dev/null | grep -v '\[✓\]' | grep -v '\[X\]' | sed 's/^/  /' || echo "  No outstanding TODOs"
        echo ""
    fi

    # Check diary entries for TODOs
    if [[ -d "${DIARY_DIR}" ]]; then
        echo -e "${BOLD}📅 TODOs from Recent Diary Entries:${RESET}"
        find "${DIARY_DIR}" -name "*.md" -type f -mtime -7 2>/dev/null | sort -r | while read -r file; do
            todos=$(grep -E '^\s*[-*]\s*\[[ ○◐●]\]' "$file" 2>/dev/null | grep -v '\[✓\]' | grep -v '\[X\]' || true)
            if [[ -n "$todos" ]]; then
                date=$(basename "$file" .md)
                echo "  [$date]"
                echo "$todos" | sed 's/^/    /'
                echo ""
            fi
        done || true
    fi

    # Check notes for TODOs
    if [[ -d "${NOTES_DIR}" ]]; then
        echo -e "${BOLD}📝 TODOs from Notes:${RESET}"
        find "${NOTES_DIR}" -name "*.md" -type f 2>/dev/null | while read -r file; do
            todos=$(grep -E '^\s*[-*]\s*\[[ ○◐●]\]' "$file" 2>/dev/null | grep -v '\[✓\]' | grep -v '\[X\]' || true)
            if [[ -n "$todos" ]]; then
                note=$(basename "$file" .md)
                echo "  [$note]"
                echo "$todos" | sed 's/^/    /'
                echo ""
            fi
        done || true
    fi

    # Summary count
    local total_incomplete
    total_incomplete=$(grep -rh -E '^\s*[-*]\s*\[[ ○◐●]\]' "${JOURNAL_DIR}" --include="*.md" 2>/dev/null | grep -v '\[✓\]' | grep -v '\[X\]' | wc -l || echo 0)
    echo -e "${HEADER}=== Summary: $total_incomplete incomplete TODOs ===${RESET}"
}

# ===== Open/Surface Commands =====

cmd_open() {
    ensure_today
    pick_jump_section
    launch_journal
}

cmd_surface() {
    ensure_today
    pick_jump_section
    if ! focus_existing_window; then
        launch_journal
    fi
}

# ===== Menu Command =====

cmd_menu() {
    log_info "Journal Menu - Select an option"
    echo ""
    echo -e "${BOLD}Available options:${RESET}"
    echo "  1. Open today's journal"
    echo "  2. Open TODO list"
    echo "  3. Review outstanding TODOs"
    echo "  4. Generate daily plan"
    echo "  5. Exit"
    echo ""
    read -p "Choose an option (1-5): " choice

    case "$choice" in
        1)
            cmd_open
            ;;
        2)
            if [[ -f "${TODO_FILE}" ]]; then
                nvim "${TODO_FILE}"
            else
                log_error "TODO file not found: ${TODO_FILE}"
            fi
            ;;
        3)
            cmd_review
            ;;
        4)
            cmd_plan
            ;;
        5)
            exit 0
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac
}

# ===== Help =====

usage() {
    cat << EOF
${HEADER}Journal Management System${RESET}

${BOLD}Usage:${RESET}
    journal.sh [COMMAND]

${BOLD}Commands:${RESET}
    ${CYAN}open${RESET}        - Open today's journal entry (default)
    ${CYAN}surface${RESET}     - Focus existing journal or open if not found
    ${CYAN}plan${RESET}        - Generate today's daily plan
    ${CYAN}review${RESET}      - Review outstanding TODOs
    ${CYAN}menu${RESET}        - Show interactive menu
    ${CYAN}help${RESET}        - Show this help message

${BOLD}Examples:${RESET}
    journal.sh open          # Open today's journal
    journal.sh surface       # Focus existing or open
    journal.sh plan          # Generate daily plan
    journal.sh review        # Show outstanding TODOs
    journal.sh menu          # Interactive menu

${BOLD}Configuration:${RESET}
    JOURNAL_DIR   - Base journal directory (default: ~/journal)
    TERMINAL      - Terminal to use (default: ghostty)
    TITLE_PREFIX  - Window title prefix (default: Journal)

EOF
}

# ===== Main =====

main() {
    local cmd="${1:-open}"

    case "$cmd" in
        open)
            cmd_open
            ;;
        surface)
            cmd_surface
            ;;
        plan)
            cmd_plan
            ;;
        review)
            cmd_review
            ;;
        menu)
            cmd_menu
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
