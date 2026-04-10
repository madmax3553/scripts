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
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

# Source common libraries
source "${HOME}/projects/scripts/lib/colors.sh"
source "${HOME}/projects/scripts/lib/common.sh"

# ===== Configuration =====

JOURNAL_DIR="${JOURNAL_DIR:-${HOME}/projects/journal}"
DIARY_DIR="${JOURNAL_DIR}/diary"
TODO_FILE="${JOURNAL_DIR}/TODO.md"
NOTES_DIR="${JOURNAL_DIR}/notes"
TERMINAL="${TERMINAL:-ghostty}"
TITLE_PREFIX="${TITLE_PREFIX:-Journal}"
JOURNAL_FLOAT_CENTER="${JOURNAL_FLOAT_CENTER:-0}"
LOG_FILE="${JOURNAL_LOG_FILE:-${XDG_STATE_HOME:-${HOME}/.local/state}/journal.log}"

# Load configuration file
CONFIG_FILE="${JOURNAL_DIR}/config/journal.conf"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

# Set defaults if config not loaded
JOURNAL_WORD_THRESHOLD="${JOURNAL_WORD_THRESHOLD:-1}"
TASK_REGISTRY="${TASK_REGISTRY:-${JOURNAL_DIR}/tasks/active.md}"
TASK_HISTORY="${TASK_HISTORY:-${JOURNAL_DIR}/tasks/history}"
REMINDER_INTERVAL="${REMINDER_INTERVAL:-7200}"
REMINDER_START_HOUR="${REMINDER_START_HOUR:-7}"
REMINDER_END_HOUR="${REMINDER_END_HOUR:-21}"
REMINDER_CHECK_INTERVAL="${REMINDER_CHECK_INTERVAL:-10}"
REMOVED_DIR="${REMOVED_DIR:-${DIARY_DIR}/.removed}"

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
    if [[ "${JOURNAL_FLOAT_CENTER}" == "1" ]]; then
        float_and_center "${FOUND_ADDR}"
    fi
}

# ===== Daily Plan Command =====

cmd_plan() {
    log_info "Generating daily plan..."
    ensure_today
    log_success "Daily plan ready at $JOURNAL_FILE"
}

# ===== Diary Index Command =====

cmd_index() {
    log_info "Generating diary index..."
    
    local index_file="${DIARY_DIR}/index.md"
    local current_month=""
    local current_year=""
    
    {
        echo "# Diary Index"
        echo ""
        echo "*Auto-generated: $(date '+%Y-%m-%d %H:%M')*"
        echo ""
        echo "[[../index|Back to Journal]]"
        echo ""
        
        # List all diary entries grouped by month (only YYYY-MM-DD.md files)
        find "${DIARY_DIR}" -maxdepth 1 -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -type f | sort -r | while read -r file; do
            local filename
            filename=$(basename "$file" .md)
            
            # Extract year and month
            local year month day
            year=$(echo "$filename" | cut -d'-' -f1)
            month=$(echo "$filename" | cut -d'-' -f2)
            day=$(echo "$filename" | cut -d'-' -f3)
            
            # Get month name
            local month_name=""
            case "$month" in
                01) month_name="January" ;;
                02) month_name="February" ;;
                03) month_name="March" ;;
                04) month_name="April" ;;
                05) month_name="May" ;;
                06) month_name="June" ;;
                07) month_name="July" ;;
                08) month_name="August" ;;
                09) month_name="September" ;;
                10) month_name="October" ;;
                11) month_name="November" ;;
                12) month_name="December" ;;
                *) month_name="Unknown" ;;
            esac
            
            # Print year header if changed
            if [[ "$year" != "$current_year" ]]; then
                current_year="$year"
                current_month=""
                echo ""
                echo "## $year"
            fi
            
            # Print month header if changed
            if [[ "$month" != "$current_month" ]]; then
                current_month="$month"
                echo ""
                echo "### $month_name"
                echo ""
            fi
            
            # Get weekday
            local weekday
            weekday=$(date -d "$filename" '+%A' 2>/dev/null || echo "")
            
            # Count TODOs
            local todo_count done_count
            todo_count=$(grep -c '^\s*[-*]\s*\[[ ○◐●]\]' "$file" 2>/dev/null || true)
            done_count=$(grep -c '^\s*[-*]\s*\[✓X\]' "$file" 2>/dev/null || true)
            [[ -z "$todo_count" ]] && todo_count=0
            [[ -z "$done_count" ]] && done_count=0
            
            # Format entry
            if [[ -n "$weekday" ]]; then
                echo "- [[$filename]] - $weekday ($todo_count pending, $done_count done)"
            else
                echo "- [[$filename]]"
            fi
        done
        
        echo ""
        echo "---"
        echo ""
        echo "## Statistics"
        echo ""
        local total_entries
        total_entries=$(find "${DIARY_DIR}" -maxdepth 1 -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -type f | wc -l)
        echo "- Total entries: $total_entries"
        
        local first_entry
        first_entry=$(find "${DIARY_DIR}" -maxdepth 1 -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -type f | sort | head -1 | xargs basename 2>/dev/null | sed 's/.md$//' || echo "N/A")
        echo "- First entry: $first_entry"
        
        local last_entry
        last_entry=$(find "${DIARY_DIR}" -maxdepth 1 -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -type f | sort -r | head -1 | xargs basename 2>/dev/null | sed 's/.md$//' || echo "N/A")
        echo "- Latest entry: $last_entry"
        
    } > "$index_file"
    
    log_success "Diary index generated at $index_file"
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

# ===== Weekly Summary Command =====

cmd_weekly() {
    local week_start week_end
    # Get Monday of current week
    week_start=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date -d "monday" +%Y-%m-%d)
    week_end=$(date -d "$week_start + 6 days" +%Y-%m-%d)
    
    local summary_file="${JOURNAL_DIR}/weekly-review-${week_start}.md"
    
    log_info "Generating weekly summary for $week_start to $week_end..."
    
    {
        echo "# Weekly Review: $week_start to $week_end"
        echo ""
        echo "*Generated: $(date '+%Y-%m-%d %H:%M')*"
        echo ""
        
        # === Journaling Stats ===
        echo "## Journaling Stats"
        echo ""
        
        local days_with_entries=0
        local total_words=0
        local entries_list=""
        
        for i in {0..6}; do
            local check_date
            check_date=$(date -d "$week_start + $i days" +%Y-%m-%d)
            local check_file="${DIARY_DIR}/${check_date}.md"
            
            if [[ -f "$check_file" ]]; then
                local word_count
                word_count=$(wc -w < "$check_file" 2>/dev/null || echo 0)
                # Only count if more than template (roughly 50 words)
                if [[ "$word_count" -gt 50 ]]; then
                    days_with_entries=$((days_with_entries + 1))
                    total_words=$((total_words + word_count))
                    local day_name
                    day_name=$(date -d "$check_date" '+%A')
                    entries_list="${entries_list}- [[$check_date]] - $day_name ($word_count words)\n"
                fi
            fi
        done
        
        echo "- Days journaled: $days_with_entries / 7"
        echo "- Total words written: $total_words"
        if [[ $days_with_entries -gt 0 ]]; then
            echo "- Average words/day: $((total_words / days_with_entries))"
        fi
        echo ""
        
        if [[ -n "$entries_list" ]]; then
            echo "### Entries This Week"
            echo ""
            echo -e "$entries_list"
        fi
        
        # === Completed Tasks ===
        echo "## Completed Tasks"
        echo ""
        
        local completed_count=0
        for i in {0..6}; do
            local check_date
            check_date=$(date -d "$week_start + $i days" +%Y-%m-%d)
            local check_file="${DIARY_DIR}/${check_date}.md"
            
            if [[ -f "$check_file" ]]; then
                local completed
                completed=$(grep -E '^\s*[-*]\s*\[✓X\]' "$check_file" 2>/dev/null || true)
                if [[ -n "$completed" ]]; then
                    echo "### $check_date"
                    echo "$completed" | sed 's/^//'
                    echo ""
                    completed_count=$((completed_count + $(echo "$completed" | wc -l)))
                fi
            fi
        done
        
        if [[ $completed_count -eq 0 ]]; then
            echo "*No completed tasks this week*"
            echo ""
        else
            echo "**Total completed: $completed_count tasks**"
            echo ""
        fi
        
        # === Carried Over Tasks ===
        echo "## Carried Over Tasks (Need Attention)"
        echo ""
        
        # Find tasks that appear in multiple days (rolled over)
        declare -A task_counts
        declare -A task_first_seen
        
        for i in {0..6}; do
            local check_date
            check_date=$(date -d "$week_start + $i days" +%Y-%m-%d)
            local check_file="${DIARY_DIR}/${check_date}.md"
            
            if [[ -f "$check_file" ]]; then
                while IFS= read -r task; do
                    # Normalize task (remove checkbox, trim)
                    local normalized
                    normalized=$(echo "$task" | sed 's/^\s*[-*]\s*\[.\]\s*//' | xargs)
                    if [[ -n "$normalized" ]]; then
                        task_counts["$normalized"]=$((${task_counts["$normalized"]:-0} + 1))
                        if [[ -z "${task_first_seen["$normalized"]:-}" ]]; then
                            task_first_seen["$normalized"]="$check_date"
                        fi
                    fi
                done < <(grep -E '^\s*[-*]\s*\[[ ○◐●]\]' "$check_file" 2>/dev/null || true)
            fi
        done
        
        local has_rollovers=0
        for task in "${!task_counts[@]}"; do
            if [[ ${task_counts["$task"]} -gt 1 ]]; then
                has_rollovers=1
                echo "- [ ] $task *(appeared ${task_counts["$task"]} times, since ${task_first_seen["$task"]})*"
            fi
        done
        
        if [[ $has_rollovers -eq 0 ]]; then
            echo "*No tasks carried over multiple days - great job!*"
        fi
        echo ""
        
        # === Outstanding from TODO.md ===
        echo "## Outstanding from Master TODO"
        echo ""
        
        if [[ -f "${TODO_FILE}" ]]; then
            local outstanding
            outstanding=$(grep -E '^\s*[-*]\s*\[[ ○◐●]\]' "${TODO_FILE}" 2>/dev/null | grep -v '\[✓\]' | grep -v '\[X\]' || true)
            if [[ -n "$outstanding" ]]; then
                echo "$outstanding"
            else
                echo "*All clear!*"
            fi
        else
            echo "*No TODO.md file found*"
        fi
        echo ""
        
        # === Next Week Planning ===
        echo "## Next Week Planning"
        echo ""
        echo "### High Priority"
        echo "- [ ] "
        echo ""
        echo "### Goals"
        echo "- [ ] "
        echo ""
        echo "### Notes"
        echo ""
        echo ""
        echo "---"
        echo "[[index|Back to Journal]] | [[diary/index|Diary Index]]"
        
    } > "$summary_file"
    
    log_success "Weekly summary generated: $summary_file"
    echo ""
    echo "Opening weekly summary..."
    nvim "$summary_file"
}

# ===== Cleanup Command =====

cmd_cleanup() {
    local dry_run=0
    if [[ "${1:-}" == "--dry-run" ]] || [[ "${1:-}" == "-n" ]]; then
        dry_run=1
        log_info "Dry run mode - no files will be deleted"
    fi
    
    log_info "Scanning for empty/unmodified diary entries..."
    echo ""
    
    local empty_files=()
    local template_only_files=()
    
    # Get template line count (approximate - templates are ~20-30 lines)
    local template_threshold=35
    local word_threshold=50
    
    while IFS= read -r file; do
        local filename
        filename=$(basename "$file" .md)
        
        # Skip today's file
        if [[ "$filename" == "$TODAY" ]]; then
            continue
        fi
        
        local line_count word_count
        line_count=$(wc -l < "$file" 2>/dev/null || echo 0)
        word_count=$(wc -w < "$file" 2>/dev/null || echo 0)
        
        # Check if file is essentially empty or just template
        if [[ $line_count -le 5 ]]; then
            empty_files+=("$file")
        elif [[ $word_count -le $word_threshold && $line_count -le $template_threshold ]]; then
            # Check if content is mostly just template headers
            local content_lines
            content_lines=$(grep -cv '^#\|^$\|^\s*-\s*$\|^\[\[' "$file" 2>/dev/null || echo 0)
            content_lines="${content_lines//[[:space:]]/}"
            if [[ -z "$content_lines" ]]; then content_lines=0; fi
            if [[ $content_lines -le 3 ]]; then
                template_only_files+=("$file")
            fi
        fi
    done < <(find "${DIARY_DIR}" -maxdepth 1 -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -type f | sort)
    
    # Report findings
    if [[ ${#empty_files[@]} -eq 0 && ${#template_only_files[@]} -eq 0 ]]; then
        log_success "No empty entries found - all diary entries have content!"
        return 0
    fi
    
    echo -e "${BOLD}Found entries to clean up:${RESET}"
    echo ""
    
    if [[ ${#empty_files[@]} -gt 0 ]]; then
        echo -e "${RED}Empty files (${#empty_files[@]}):${RESET}"
        for f in "${empty_files[@]}"; do
            echo "  - $(basename "$f" .md)"
        done
        echo ""
    fi
    
    if [[ ${#template_only_files[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Template-only files (${#template_only_files[@]}):${RESET}"
        for f in "${template_only_files[@]}"; do
            local wc
            wc=$(wc -w < "$f" 2>/dev/null || echo 0)
            echo "  - $(basename "$f" .md) ($wc words)"
        done
        echo ""
    fi
    
    if [[ $dry_run -eq 1 ]]; then
        echo -e "${CYAN}Dry run complete. Run without --dry-run to delete these files.${RESET}"
        return 0
    fi
    
    # Confirm deletion
    local total=$((${#empty_files[@]} + ${#template_only_files[@]}))
    echo -e "${YELLOW}This will delete $total file(s).${RESET}"
    read -p "Continue? (y/N): " confirm
    
    if [[ "${confirm,,}" != "y" && "${confirm,,}" != "yes" ]]; then
        log_info "Cleanup cancelled."
        return 0
    fi
    
    # Delete files
    local deleted=0
    for f in "${empty_files[@]}" "${template_only_files[@]}"; do
        if rm "$f" 2>/dev/null; then
            deleted=$((deleted + 1))
            echo "  Deleted: $(basename "$f")"
        else
            log_error "Failed to delete: $f"
        fi
    done
    
    log_success "Cleaned up $deleted file(s)"
    
    # Regenerate index
    echo ""
    log_info "Regenerating diary index..."
    cmd_index
}

# ===== Task Management Functions =====

check_journalled() {
    local file="${1:-.}"
    
    # Count actual content words (exclude headers, task lines, metadata)
    local content_words
    content_words=$(grep -v "^#\|^-\|^$\|^!!\|^---\|^!\[\|^\[" "$file" 2>/dev/null | wc -w || echo 0)
    
    # Trim whitespace
    content_words=$(echo "$content_words" | xargs)
    
    if [[ $content_words -ge $JOURNAL_WORD_THRESHOLD ]]; then
        return 0  # Journalled!
    else
        return 1  # Not journalled yet
    fi
}

cleanup_non_journalled() {
    log_info "Scanning for non-journalled entries..."
    
    mkdir -p "${REMOVED_DIR}"
    local cleaned=0
    local temp_file="/tmp/cleanup_list_$$.txt"
    
    # Generate list of files to remove
    find "${DIARY_DIR}" -maxdepth 1 -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -type f | sort > "$temp_file"
    
    while IFS= read -r file; do
        local filename
        filename=$(basename "$file")
        
        # Skip today's file
        if [[ "$filename" == "${TODAY}.md" ]]; then
            continue
        fi
        
        # Check if file meets journalled threshold
        local content_words
        content_words=$(grep -v "^#\|^-\|^$\|^!!\|^---\|^!\[\|^\[" "$file" 2>/dev/null | wc -w)
        content_words=${content_words:-0}
        content_words=$((content_words))  # Force numeric conversion
        
        if (( content_words < JOURNAL_WORD_THRESHOLD )); then
            # Archive to .removed directory
            if mv "$file" "${REMOVED_DIR}/${filename}.bak" 2>/dev/null; then
                cleaned=$((cleaned + 1))
                journal_log "cleanup: removed non-journalled entry ${filename}"
            fi
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [[ $cleaned -gt 0 ]]; then
        log_success "Cleaned up $cleaned non-journalled entries"
    fi
}

task_next_id() {
    # Generate next sequential task ID
    if [[ ! -f "${TASK_REGISTRY}" ]]; then
        echo "task_1"
        return 0
    fi
    
    local last_id
    last_id=$(grep "^ID: task_" "${TASK_REGISTRY}" 2>/dev/null | tail -1 | sed 's/^ID: task_//' || echo "0")
    echo "task_$((last_id + 1))"
}

task_add() {
    local title="${1:-}"
    
    if [[ -z "$title" ]]; then
        log_error "Task title required"
        return 1
    fi
    
    mkdir -p "$(dirname "${TASK_REGISTRY}")"
    
    local task_id
    task_id=$(task_next_id)
    local timestamp
    timestamp=$(date +%Y-%m-%d)
    
    # Add to registry
    {
        echo ""
        echo "## Task: $title"
        echo "ID: $task_id"
        echo "Created: $timestamp"
        echo "Status: [ ]"
        echo "Source: diary/${TODAY}.md"
    } >> "${TASK_REGISTRY}"
    
    # Add to today's journal
    if [[ -f "${JOURNAL_FILE}" ]]; then
        # Find the "Tasks for Tomorrow" or appropriate section and add before it
        if grep -q "^## Tasks for Tomorrow" "${JOURNAL_FILE}"; then
            sed -i "/^## Tasks for Tomorrow/i - [ ] [$task_id] $title" "${JOURNAL_FILE}"
        elif grep -q "^## Next Week Prep" "${JOURNAL_FILE}"; then
            sed -i "/^## Next Week Prep/i - [ ] [$task_id] $title" "${JOURNAL_FILE}"
        else
            # Append to end if no matching section
            echo "- [ ] [$task_id] $title" >> "${JOURNAL_FILE}"
        fi
    fi
    
    log_success "Task added: $task_id - $title"
}

task_check() {
    local task_id="${1:-}"
    
    if [[ -z "$task_id" ]]; then
        log_error "Task ID required"
        return 1
    fi
    
    if [[ ! -f "${TASK_REGISTRY}" ]]; then
        log_error "Task registry not found"
        return 1
    fi
    
    # Mark as completed in registry
    if grep -q "^ID: $task_id$" "${TASK_REGISTRY}"; then
        sed -i "/^ID: $task_id$/,/^---$/s/^Status: \[ \]$/Status: [x]/" "${TASK_REGISTRY}"
        log_success "Task marked complete: $task_id"
    else
        log_error "Task not found: $task_id"
        return 1
    fi
}

task_list_active() {
    if [[ ! -f "${TASK_REGISTRY}" ]]; then
        echo "No active tasks"
        return 0
    fi
    
    echo -e "${BOLD}Active Tasks:${RESET}"
    echo ""
    
    awk '
        /^## Task:/ {
            task=$0; gsub(/^## Task: /, "", task)
            getline; id=$0; gsub(/^ID: /, "", id)
            getline; created=$0; gsub(/^Created: /, "", created)
            getline; status=$0; gsub(/^Status: /, "", status)
            getline; source=$0; gsub(/^Source: /, "", source)
            
            if (status ~ /\[ \]/) {
                printf "  [%s] %s (%s)\n", id, task, created
            }
        }
    ' "${TASK_REGISTRY}"
    echo ""
}

update_dashboard() {
    log_info "Updating journal dashboard..."
    
    local dashboard_file="${JOURNAL_DIR}/index.md"
    
    # Generate dashboard
    {
        echo "# Journal Dashboard"
        echo ""
        echo "*Last updated: $(date '+%Y-%m-%d %H:%M')*"
        echo ""
        echo "## 📊 Habit Metrics"
        echo ""
        echo "- **Current Streak:** Calculating..."
        echo "- **This Month:** Calculating..."
        echo ""
        echo "## 📋 Outstanding Tasks"
        echo ""
        echo "- Task system ready"
        echo ""
        echo "## 🔗 Quick Links"
        echo ""
        echo "- [[diary/${TODAY}|Today]]"
        echo "- [[diary/index|All Entries]]"
        echo "- [[TODO|Main TODO List]]"
        
    } > "$dashboard_file"
    
    log_success "Dashboard updated: $dashboard_file"
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
    ${CYAN}open${RESET}                   - Open today's journal entry (default)
    ${CYAN}surface${RESET}                - Focus existing journal or open if not found
    ${CYAN}plan${RESET}                   - Generate today's daily plan
    ${CYAN}review${RESET}                 - Review outstanding TODOs
    ${CYAN}index${RESET}                  - Generate diary index
    ${CYAN}weekly${RESET}                 - Generate weekly summary (stats, completed tasks, etc.)
    ${CYAN}cleanup_non_journalled${RESET} - Remove non-journalled entries (cron-safe)
    ${CYAN}update_dashboard${RESET}       - Update journal dashboard with stats and tasks
    ${CYAN}menu${RESET}                   - Show interactive menu
    ${CYAN}help${RESET}                   - Show this help message

${BOLD}Examples:${RESET}
    journal.sh open          # Open today's journal
    journal.sh surface       # Focus existing or open
    journal.sh plan          # Generate daily plan
    journal.sh review        # Show outstanding TODOs
    journal.sh index         # Regenerate diary index
    journal.sh weekly        # Generate and open weekly summary
    journal.sh cleanup --dry-run  # Preview cleanup (no deletion)
    journal.sh cleanup       # Remove empty entries (with confirmation)
    journal.sh menu          # Interactive menu

${BOLD}Configuration:${RESET}
    JOURNAL_DIR   - Base journal directory (default: ~/journal)
    TERMINAL      - Terminal to use (default: ghostty)
    TITLE_PREFIX  - Window title prefix (default: Journal)
    JOURNAL_FLOAT_CENTER - Force float+center after launch (default: 0)

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
        index)
            cmd_index
            ;;
        weekly)
            cmd_weekly
            ;;
        cleanup_non_journalled)
            cleanup_non_journalled
            ;;
        cleanup)
            shift
            cmd_cleanup "$@"
            ;;
        update_dashboard)
            update_dashboard
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
