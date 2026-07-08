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
# Modified: 2026-07-08

set -euo pipefail

# Source common libraries
source "${HOME}/projects/scripts/lib/colors.sh"
source "${HOME}/projects/scripts/lib/common.sh"

# ===== Configuration =====

JOURNAL_DIR="${JOURNAL_DIR:-${HOME}/projects/journal}"
DIARY_DIR="${JOURNAL_DIR}/diary"
TODO_FILE="${JOURNAL_DIR}/TODO.md"
DASHBOARD_FILE="${JOURNAL_DIR}/index.md"
NOTES_DIR="${JOURNAL_DIR}/notes"
WATCHLIST_FILE="${NOTES_DIR}/watchlist.md"
WATCHLIST_SCRIPT="${WATCHLIST_SCRIPT:-${HOME}/.local/bin/update_watchlist.py}"
READLIST_FILE="${NOTES_DIR}/readlist.md"
READLIST_SCRIPT="${READLIST_SCRIPT:-${HOME}/projects/scripts/journal/update_readlist.py}"
TABS_FILE="${NOTES_DIR}/tabs.md"
TERMINAL="${TERMINAL:-ghostty}"
TITLE_PREFIX="${TITLE_PREFIX:-Journal}"
DASHBOARD_TITLE="${TITLE_PREFIX} Dashboard"
TODO_TITLE="${TITLE_PREFIX} TODO"
WATCHLIST_TITLE="${TITLE_PREFIX} Watchlist"
READLIST_TITLE="${TITLE_PREFIX} Readlist"
TABS_TITLE="${TITLE_PREFIX} Tabs"
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
TODO_PROMOTE_MEDIUM_AGE_DAYS="${TODO_PROMOTE_MEDIUM_AGE_DAYS:-14}"
TODO_PROMOTE_LOW_AGE_DAYS="${TODO_PROMOTE_LOW_AGE_DAYS:-30}"

if ! declare -p JOURNAL_GIT_REPOS >/dev/null 2>&1; then
    JOURNAL_GIT_REPOS=(
        "${JOURNAL_DIR}"
        "${HOME}/projects/scripts"
        "${HOME}/dotfiles"
    )
fi

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

focus_window_by_title() {
    local title="$1"

    command -v hyprctl >/dev/null 2>&1 || return 1

    local address
    address="$(
        hyprctl -j clients 2>/dev/null | jq -r --arg title "${title}" '
            map(select(
                (.title // "" ) == $title or
                (.initialTitle // "" ) == $title
            )) |
            max_by(.pid // 0) | .address // empty
        ' 2>/dev/null || echo ""
    )"

    if [[ -z "${address}" ]]; then
        journal_log "focus: no matching window found (title=${title})"
        return 1
    fi

    FOUND_ADDR="${address}"
    journal_log "focus: focusing address ${address}"
    hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1 || journal_log "focus: dispatch failed"
    return 0
}

focus_existing_window() {
    focus_window_by_title "${TITLE}"
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

    local tasks_file new_tasks tmp
    tasks_file="$(mktemp)"
    new_tasks="$(mktemp)"
    tmp="$(mktemp)"

    awk '
        /^## Tasks for Tomorrow$/ { in_tasks = 1; next }
        in_tasks && /^## / { in_tasks = 0 }
        in_tasks && /^- \[ \]/ { print }
    ' "${yesterday_file}" > "${tasks_file}" || true
    if [[ ! -s "${tasks_file}" ]]; then
        rm -f "${tasks_file}" "${new_tasks}" "${tmp}"
        return 0
    fi

    local task
    while IFS= read -r task; do
        [[ -n "${task}" ]] || continue
        if ! grep -Fqx -- "${task}" "${JOURNAL_FILE}"; then
            printf '%s\n' "${task}" >> "${new_tasks}"
        fi
    done < "${tasks_file}"

    if [[ ! -s "${new_tasks}" ]]; then
        rm -f "${tasks_file}" "${new_tasks}" "${tmp}"
        return 0
    fi

    awk -v tasks_file="${new_tasks}" '
        { print }

        /^## Tasks Carried Over from Yesterday$/ {
            while ((getline task < tasks_file) > 0) {
                print task
            }
            close(tasks_file)
            inserted = 1
        }

        END {
            if (!inserted) {
                print ""
                print "## Tasks Carried Over from Yesterday"
                while ((getline task < tasks_file) > 0) {
                    print task
                }
                close(tasks_file)
            }
        }
    ' "${JOURNAL_FILE}" > "${tmp}"

    mv "${tmp}" "${JOURNAL_FILE}"
    rm -f "${tasks_file}" "${new_tasks}"
}

collect_priority_todos() {
    [[ -f "${TODO_FILE}" ]] || return 0

    awk '
        /^## / {
            section = substr($0, 4)
            next
        }

        section == "High Priority" { priority = "High" }
        section == "Medium Priority" { priority = "Medium" }
        section == "Low Priority" { priority = "Low" }
        section != "High Priority" && section != "Medium Priority" && section != "Low Priority" { priority = "" }

        priority != "" && /^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\]/ {
            item = $0
            sub(/^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\][[:space:]]*/, "", item)
            gsub(/\t/, " ", item)
            print priority "\t" section "\t" NR "\t" item
        }
    ' "${TODO_FILE}"
}

todo_is_weekend_tagged() {
    local item="${1,,}"

    [[ "${item}" =~ (^|[[:space:]])#weekends?($|[[:space:][:punct:]]) ]] ||
        [[ "${item}" =~ (^|[[:space:]])@weekends?($|[[:space:][:punct:]]) ]] ||
        [[ "${item}" =~ \[weekends?\] ]] ||
        [[ "${item}" =~ \(weekends?\) ]]
}

render_todo_rows() {
    local rows_file="$1"
    local mode="$2"
    local limit="$3"
    local count=0
    local priority section line item

    while IFS=$'\t' read -r priority section line item; do
        [[ -n "${item}" ]] || continue

        case "${mode}" in
            high)
                [[ "${priority}" == "High" ]] || continue
                ;;
            weekend)
                todo_is_weekend_tagged "${item}" || continue
                ;;
        esac

        printf -- '- [[../TODO|TODO.md]] `%s` %s\n' "${priority}" "${item}"
        count=$((count + 1))
        (( count >= limit )) && break
    done < "${rows_file}"

    if (( count == 0 )); then
        case "${mode}" in
            weekend)
                echo "- No priority TODOs tagged yet. Add \`#weekend\` to pin one here."
                ;;
            *)
                echo "- No matching priority TODOs."
                ;;
        esac
    fi
}

render_longest_todo_rows() {
    local rows_file="$1"
    local limit="$2"
    local scored
    scored="$(mktemp)"

    local priority section line item age sort_age age_label
    while IFS=$'\t' read -r priority section line item; do
        [[ -n "${item}" ]] || continue

        age="$(todo_age_days "${item}" || true)"
        if [[ "${age}" =~ ^[0-9]+$ ]]; then
            sort_age="${age}"
            age_label="${age}d"
        else
            sort_age=0
            age_label="age unknown"
        fi

        printf '%08d\t%08d\t%s\t%s\t%s\n' "${sort_age}" "${line}" "${priority}" "${age_label}" "${item}" >> "${scored}"
    done < "${rows_file}"

    if [[ ! -s "${scored}" ]]; then
        echo "- No priority TODOs."
        rm -f "${scored}"
        return 0
    fi

    sort -t $'\t' -k1,1nr -k2,2n "${scored}" | head -n "${limit}" | while IFS=$'\t' read -r sort_age line priority age_label item; do
        printf -- '- [[../TODO|TODO.md]] `%s` %s *(%s)*\n' "${priority}" "${item}" "${age_label}"
    done

    rm -f "${scored}"
}

render_daily_todo_focus() {
    echo "## TODO Focus"
    echo ""
    echo "*Auto-generated: $(date '+%Y-%m-%d %H:%M %Z'). Source: [[../TODO|TODO.md]]*"
    echo ""

    if [[ ! -f "${TODO_FILE}" ]]; then
        echo "- TODO.md not found: ${TODO_FILE}"
        echo ""
        return 0
    fi

    local rows_file total
    rows_file="$(mktemp)"
    collect_priority_todos > "${rows_file}"
    total="$(wc -l < "${rows_file}" | tr -d ' ')"

    echo "- Open priority TODOs: ${total}"
    echo "- Master list: [[../TODO|TODO.md]]"
    echo ""
    echo "### Most Important"
    render_todo_rows "${rows_file}" high 3
    echo ""
    echo "### Weekend Tagged"
    render_todo_rows "${rows_file}" weekend 3
    echo ""
    echo "### Longest Open"
    render_longest_todo_rows "${rows_file}" 3
    echo ""

    rm -f "${rows_file}"
}

strip_daily_todo_focus() {
    awk '
        /^## TODO Focus$/ { skip=1; next }
        /^## / && skip { skip=0 }
        !skip { print }
    ' "$1"
}

insert_daily_todo_focus() {
    local source_file="$1"
    local block_file="$2"

    awk -v block_file="${block_file}" '
        BEGIN {
            while ((getline line < block_file) > 0) {
                block = block line ORS
            }
            close(block_file)
        }

        in_carryover && /^[[:space:]]*$/ {
            next
        }

        in_carryover && /^## / {
            print ""
            printf "%s", block
            inserted = 1
            in_carryover = 0
        }

        { print }

        /^## Tasks Carried Over from Yesterday$/ {
            in_carryover = 1
        }

        END {
            if (!inserted) {
                print ""
                printf "%s", block
            }
        }
    ' "${source_file}"
}

update_daily_todo_focus() {
    [[ -f "${JOURNAL_FILE}" ]] || return 0

    local stripped block tmp
    stripped="$(mktemp)"
    block="$(mktemp)"
    tmp="$(mktemp)"

    render_daily_todo_focus > "${block}"
    strip_daily_todo_focus "${JOURNAL_FILE}" > "${stripped}"
    insert_daily_todo_focus "${stripped}" "${block}" > "${tmp}"

    trim_trailing_blank_lines "${tmp}"
    mv "${tmp}" "${JOURNAL_FILE}"
    rm -f "${stripped}" "${block}"

    journal_log "updated daily todo focus: ${JOURNAL_FILE}"
}

git_repo_label() {
    local repo="$1"

    if [[ "${repo}" == "${JOURNAL_DIR}" ]]; then
        echo "journal"
        return 0
    fi

    basename "${repo}"
}

render_daily_git_commits() {
    local since until repo label commits found=0
    since="${TODAY} 00:00"
    until="${TODAY} 23:59:59"

    echo "## Git Commits Today"
    echo ""
    echo "*Auto-generated: $(date '+%Y-%m-%d %H:%M %Z')*"
    echo ""

    for repo in "${JOURNAL_GIT_REPOS[@]}"; do
        [[ -d "${repo}/.git" ]] || continue

        label="$(git_repo_label "${repo}")"
        commits="$(git -C "${repo}" log --since="${since}" --until="${until}" --date=short --pretty=format:'- `%h` %s' 2>/dev/null || true)"
        [[ -n "${commits}" ]] || continue

        found=1
        echo "### ${label}"
        echo "${commits}"
        echo ""
    done

    if [[ "${found}" -eq 0 ]]; then
        echo "- No commits recorded yet."
        echo ""
    fi
}

update_daily_git_commits() {
    [[ -f "${JOURNAL_FILE}" ]] || return 0

    local tmp block
    tmp="$(mktemp)"
    block="$(mktemp)"

    render_daily_git_commits > "${block}"

    awk '
        /^## Git Commits Today$/ { skip=1; next }
        /^## / && skip { skip=0 }
        !skip { print }
    ' "${JOURNAL_FILE}" > "${tmp}"

    while [[ -s "${tmp}" && -z "$(tail -n 1 "${tmp}")" ]]; do
        sed -i '$d' "${tmp}"
    done
    printf '\n' >> "${tmp}"
    cat "${block}" >> "${tmp}"
    while [[ -s "${tmp}" && -z "$(tail -n 1 "${tmp}")" ]]; do
        sed -i '$d' "${tmp}"
    done
    mv "${tmp}" "${JOURNAL_FILE}"
    rm -f "${block}"

    journal_log "updated daily git commits: ${JOURNAL_FILE}"
}

strip_daily_git_commits() {
    awk '
        /^## Git Commits Today$/ { skip=1; next }
        /^## / && skip { skip=0 }
        !skip { print }
    ' "$1"
}

trim_trailing_blank_lines() {
    local file="$1"

    while [[ -s "${file}" && -z "$(tail -n 1 "${file}")" ]]; do
        sed -i '$d' "${file}"
    done
}

journal_has_template() {
    [[ -f "${JOURNAL_FILE}" ]] || return 1

    if [[ "${IS_WEEKEND}" -eq 1 ]]; then
        grep -Eq '^## This Weekend Intentions$' "${JOURNAL_FILE}" &&
            grep -Eq '^## Next Week Prep$' "${JOURNAL_FILE}"
    else
        grep -Eq '^## Morning$' "${JOURNAL_FILE}" &&
            grep -Eq '^## Tasks for Tomorrow$' "${JOURNAL_FILE}"
    fi
}

create_today_template() {
    journal_log "creating template: weekend=${IS_WEEKEND} file=${JOURNAL_FILE}"
    if [[ "${IS_WEEKEND}" -eq 1 ]]; then
        create_template_weekend
    else
        create_template_weekday
    fi
    carry_forward_tasks
}

recover_untemplated_journal() {
    local recovered
    recovered="$(mktemp)"

    strip_daily_git_commits "${JOURNAL_FILE}" > "${recovered}"
    trim_trailing_blank_lines "${recovered}"

    create_today_template

    if grep -q '[^[:space:]]' "${recovered}"; then
        {
            echo ""
            echo "## Recovered Notes"
            echo ""
            cat "${recovered}"
        } >> "${JOURNAL_FILE}"
    fi

    rm -f "${recovered}"
    journal_log "recovered untemplated journal: ${JOURNAL_FILE}"
}

ensure_today() {
    if [[ ! -f "${JOURNAL_FILE}" ]]; then
        create_today_template
        log_success "Created today's journal entry"
        journal_log "updating watchlist streaming info..."
        timeout 60 "${WATCHLIST_SCRIPT}" \
            --watchlist "${WATCHLIST_FILE}" \
            --archive-watched \
            --append-diary "${JOURNAL_FILE}" || journal_log "watchlist update failed"
    elif ! journal_has_template; then
        recover_untemplated_journal
        log_success "Restored today's journal template"
    else
        journal_log "journal exists: ${JOURNAL_FILE}"
    fi

    update_daily_todo_focus
    update_daily_git_commits
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

launch_markdown_file() {
    local title="$1"
    local file="$2"
    local cmd=()
    local nvim_full=(nvim "+set notitle" "${file}")

    journal_log "launch: terminal=${TERMINAL} title=\"${title}\" file=${file}"

    case "${TERMINAL}" in
        ghostty)
            cmd=(ghostty --title="${title}" -e "${nvim_full[@]}")
            ;;
        kitty)
            cmd=(kitty --class Journal --title "${title}" "${nvim_full[@]}")
            ;;
        alacritty)
            cmd=(alacritty --class Journal --title "${title}" -e "${nvim_full[@]}")
            ;;
        *)
            cmd=("${TERMINAL}" -e "${nvim_full[@]}")
            ;;
    esac

    setsid "${cmd[@]}" >/dev/null 2>&1 &
}

# ===== Daily Plan Command =====

cmd_plan() {
    log_info "Generating daily plan..."
    ensure_today
    log_success "Daily plan ready at $JOURNAL_FILE"
}

# ===== Daily Git Commits Command =====

cmd_commits() {
    log_info "Updating today's git commit summary..."
    ensure_today
    log_success "Git commit summary updated in ${JOURNAL_FILE}"
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

cmd_dashboard() {
    ensure_today
    launch_markdown_file "${DASHBOARD_TITLE}" "${DASHBOARD_FILE}"
}

cmd_surface_dashboard() {
    ensure_today
    if ! focus_window_by_title "${DASHBOARD_TITLE}"; then
        launch_markdown_file "${DASHBOARD_TITLE}" "${DASHBOARD_FILE}"
    fi
}

cmd_todo() {
    launch_markdown_file "${TODO_TITLE}" "${TODO_FILE}"
}

cmd_surface_todo() {
    if ! focus_window_by_title "${TODO_TITLE}"; then
        launch_markdown_file "${TODO_TITLE}" "${TODO_FILE}"
    fi
}

# Frozen browser tabs (iced) — the DB is owned by launcher/iced.sh and lives
# in notes/ so it rides along with journal git backups.  iced.sh delegates
# its "edit" pathway to surface-tabs so every entry point shares one window.
cmd_tabs() {
    if [[ ! -f "${TABS_FILE}" ]]; then
        log_error "Tabs file not found: ${TABS_FILE} (freeze a tab with iced.sh first)"
        exit 1
    fi
    launch_markdown_file "${TABS_TITLE}" "${TABS_FILE}"
}

cmd_surface_tabs() {
    if ! focus_window_by_title "${TABS_TITLE}"; then
        cmd_tabs
    fi
}

cmd_watchlist() {
    local subcmd="${1:-open}"
    shift || true

    case "${subcmd}" in
        open)
            if [[ -f "${WATCHLIST_FILE}" ]]; then
                launch_markdown_file "${WATCHLIST_TITLE}" "${WATCHLIST_FILE}"
            else
                log_error "Watchlist file not found: ${WATCHLIST_FILE}"
                exit 1
            fi
            ;;
        update)
            log_info "Updating watchlist availability and archive..."
            "${WATCHLIST_SCRIPT}" \
                --watchlist "${WATCHLIST_FILE}" \
                --archive-watched \
                "$@"
            ;;
        archive)
            log_info "Archiving checked watchlist items..."
            "${WATCHLIST_SCRIPT}" \
                --watchlist "${WATCHLIST_FILE}" \
                --no-streaming \
                --archive-watched \
                "$@"
            ;;
        suggest)
            if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
                local count="$1"
                shift
                set -- --suggest-count "${count}" "$@"
            fi

            log_info "Requesting watchlist suggestions from agy..."
            "${WATCHLIST_SCRIPT}" \
                --watchlist "${WATCHLIST_FILE}" \
                --no-streaming \
                --suggest \
                "$@"
            ;;
        import)
            local export_file="${1:-}"
            if [[ -z "${export_file}" ]]; then
                log_error "Usage: journal.sh watchlist import <justwatch-export.json>"
                exit 1
            fi
            shift
            log_info "Importing JustWatch watchlist export..."
            "${WATCHLIST_SCRIPT}" \
                --watchlist "${WATCHLIST_FILE}" \
                --no-streaming \
                --import-justwatch "${export_file}" \
                "$@"
            ;;
        help|--help|-h)
            cat << EOF
${HEADER}Watchlist Commands${RESET}

${BOLD}Usage:${RESET}
    journal.sh watchlist [open|update|archive|suggest|import]

${BOLD}Commands:${RESET}
    ${CYAN}open${RESET}             - Open notes/watchlist.md
    ${CYAN}update${RESET}           - Refresh JustWatch statuses and archive watched items
    ${CYAN}archive${RESET}          - Archive checked items without refreshing streaming data
    ${CYAN}suggest [count]${RESET}  - Ask agy for suggestions and add them to the inbox
    ${CYAN}import <file>${RESET}    - Add new titles from a JustWatch watchlist JSON export

EOF
            ;;
        *)
            log_error "Unknown watchlist command: ${subcmd}"
            cmd_watchlist help
            exit 1
            ;;
    esac
}

cmd_readlist() {
    local subcmd="${1:-open}"
    shift || true

    case "${subcmd}" in
        open)
            if [[ -f "${READLIST_FILE}" ]]; then
                launch_markdown_file "${READLIST_TITLE}" "${READLIST_FILE}"
            else
                log_error "Readlist file not found: ${READLIST_FILE}"
                exit 1
            fi
            ;;
        import)
            log_info "Importing Audible library into readlist..."
            "${READLIST_SCRIPT}" \
                --readlist "${READLIST_FILE}" \
                --archive-finished \
                "$@"
            ;;
        sync)
            log_info "Syncing Audible library against readlist..."
            "${READLIST_SCRIPT}" \
                --readlist "${READLIST_FILE}" \
                --sync \
                "$@"
            ;;
        archive)
            log_info "Archiving checked readlist items..."
            "${READLIST_SCRIPT}" \
                --readlist "${READLIST_FILE}" \
                --no-import \
                --archive-finished \
                "$@"
            ;;
        help|--help|-h)
            cat << EOF
${HEADER}Readlist Commands${RESET}

${BOLD}Usage:${RESET}
    journal.sh readlist [open|import|sync|archive]

${BOLD}Commands:${RESET}
    ${CYAN}open${RESET}             - Open notes/readlist.md
    ${CYAN}import${RESET}           - Import titles from Audible HTML and archive checked items
    ${CYAN}sync${RESET}             - Import, compare owned set (delta), and fill missing metadata
    ${CYAN}archive${RESET}          - Archive checked read items without importing

${BOLD}Examples:${RESET}
    journal.sh readlist import --audible-html ~/Downloads/Audible\ Library.html
    journal.sh readlist import --fetch-audible-browser --audible-domain www.audible.ca
    journal.sh readlist sync --fetch-audible-browser --audible-domain www.audible.ca
    journal.sh readlist import --fetch-audible-api --audible-cookie-file ~/Downloads/audible-cookies.txt --audible-cookie-file ~/Downloads/amazon-cookies.txt
    journal.sh readlist archive

EOF
            ;;
        *)
            log_error "Unknown readlist command: ${subcmd}"
            cmd_readlist help
            exit 1
            ;;
    esac
}

# ===== Weekly Summary Command =====

todo_item_text() {
    local line="$1"
    line="${line#*- [ ] }"
    line="${line#* [ ] }"
    printf '%s\n' "$line" | sed 's/[[:space:]]*$//'
}

todo_age_days() {
    local item_text="$1"
    local todo_rel="TODO.md"

    [[ -n "${item_text}" ]] || return 1
    [[ -d "${JOURNAL_DIR}/.git" ]] || return 1

    local first_seen
    first_seen=$(git -C "${JOURNAL_DIR}" log --follow --reverse --format='%ad' --date=short -S"${item_text}" -- "${todo_rel}" 2>/dev/null | head -n 1 || true)
    [[ -n "${first_seen}" ]] || return 1

    local first_epoch today_epoch
    first_epoch=$(date -d "${first_seen}" +%s 2>/dev/null || true)
    today_epoch=$(date -d "${TODAY}" +%s 2>/dev/null || true)
    [[ -n "${first_epoch}" && -n "${today_epoch}" ]] || return 1

    echo $(((today_epoch - first_epoch) / 86400))
}

cleanup_completed_todos() {
    [[ -f "${TODO_FILE}" ]] || return 0

    mkdir -p "${TASK_HISTORY}"

    local tmp_file completed_file archived_count
    tmp_file=$(mktemp)
    completed_file=$(mktemp)
    archived_count=0

    awk -v completed_file="${completed_file}" '
        /^## Completed$/ { in_completed=1; print; next }
        /^## / && in_completed && $0 != "## Completed" { in_completed=0 }

        in_completed && /^[[:space:]]*[-*][[:space:]]*\[[✓xX]\]/ {
            print > completed_file
            next
        }

        { print }
    ' "${TODO_FILE}" > "${tmp_file}"

    archived_count=$(grep -c '^[[:space:]]*[-*][[:space:]]*\[[✓xX]\]' "${completed_file}" 2>/dev/null || true)
    archived_count="${archived_count//[[:space:]]/}"

    if (( archived_count > 0 )); then
        local history_file="${TASK_HISTORY}/completed-${TODAY}.md"
        {
            echo "## Completed TODO cleanup: ${TODAY}"
            echo ""
            cat "${completed_file}"
            echo ""
        } >> "${history_file}"
        mv "${tmp_file}" "${TODO_FILE}"
        log_success "Archived ${archived_count} completed TODO item(s) to ${history_file}"
    else
        rm -f "${tmp_file}"
    fi

    rm -f "${completed_file}"
}

promote_aged_todos() {
    [[ -f "${TODO_FILE}" ]] || return 0

    local tmp_file promoted_file
    tmp_file=$(mktemp)
    promoted_file=$(mktemp)

    local section="prefix"
    local -a prefix high medium low suffix
    local -a promoted_high promoted_medium
    local line item_text age_days

    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            "## High Priority") section="high"; continue ;;
            "## Medium Priority") section="medium"; continue ;;
            "## Low Priority") section="low"; continue ;;
            "## Ongoing Git Changes"|"## Completed"|"## Tips") section="suffix" ;;
        esac

        case "${section}" in
            prefix) prefix+=("${line}") ;;
            high) high+=("${line}") ;;
            medium)
                if [[ "${line}" =~ ^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\] ]]; then
                    item_text=$(todo_item_text "${line}")
                    age_days=$(todo_age_days "${item_text}" || true)
                    if [[ -n "${age_days}" ]] && (( age_days >= TODO_PROMOTE_MEDIUM_AGE_DAYS )); then
                        promoted_high+=("${line}")
                        printf '%s\n' "- Medium -> High after ${age_days} days: ${item_text}" >> "${promoted_file}"
                        continue
                    fi
                fi
                medium+=("${line}")
                ;;
            low)
                if [[ "${line}" =~ ^[[:space:]]*[-*][[:space:]]*\[[[:space:]]\] ]]; then
                    item_text=$(todo_item_text "${line}")
                    age_days=$(todo_age_days "${item_text}" || true)
                    if [[ -n "${age_days}" ]] && (( age_days >= TODO_PROMOTE_LOW_AGE_DAYS )); then
                        promoted_medium+=("${line}")
                        printf '%s\n' "- Low -> Medium after ${age_days} days: ${item_text}" >> "${promoted_file}"
                        continue
                    fi
                fi
                low+=("${line}")
                ;;
            suffix) suffix+=("${line}") ;;
        esac
    done < "${TODO_FILE}"

    if [[ ! -s "${promoted_file}" ]]; then
        rm -f "${tmp_file}" "${promoted_file}"
        return 0
    fi

    {
        printf '%s\n' "${prefix[@]}"
        echo "## High Priority"
        printf '%s\n' "${high[@]}"
        printf '%s\n' "${promoted_high[@]}"
        echo "## Medium Priority"
        printf '%s\n' "${medium[@]}"
        printf '%s\n' "${promoted_medium[@]}"
        echo "## Low Priority"
        printf '%s\n' "${low[@]}"
        printf '%s\n' "${suffix[@]}"
    } > "${tmp_file}"

    mv "${tmp_file}" "${TODO_FILE}"
    log_success "Promoted aged TODO item(s):"
    sed 's/^/  /' "${promoted_file}"
    rm -f "${promoted_file}"
}

maintain_weekly_todos() {
    cleanup_completed_todos
    promote_aged_todos
}

cmd_weekly() {
    local open_editor=1
    if [[ "${1:-}" == "--no-open" ]] || [[ "${1:-}" == "--cron" ]]; then
        open_editor=0
    fi

    local week_start week_end
    # Get Monday of current week
    week_start=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date -d "monday" +%Y-%m-%d)
    week_end=$(date -d "$week_start + 6 days" +%Y-%m-%d)
    
    local summary_file="${JOURNAL_DIR}/weekly-review-${week_start}.md"
    
    log_info "Generating weekly summary for $week_start to $week_end..."
    maintain_weekly_todos
    
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
    if [[ "${open_editor}" -eq 1 ]]; then
        echo ""
        echo "Opening weekly summary..."
        nvim "$summary_file"
    fi
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
        echo "- [[notes/tabs|Frozen Tabs (iced)]]"
        
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
    ${CYAN}dashboard${RESET}              - Open journal dashboard
    ${CYAN}surface-dashboard${RESET}      - Focus existing dashboard or open if not found
    ${CYAN}todo${RESET}                   - Open master TODO list
    ${CYAN}surface-todo${RESET}           - Focus existing TODO list or open if not found
    ${CYAN}tabs${RESET}                   - Open frozen browser tabs (iced) list
    ${CYAN}surface-tabs${RESET}           - Focus existing tabs list or open if not found
    ${CYAN}watchlist${RESET}              - Open/update/archive/suggest watchlist items
    ${CYAN}readlist${RESET}               - Open/import/archive readlist items
    ${CYAN}plan${RESET}                   - Generate today's daily plan
    ${CYAN}commits${RESET}                - Update today's diary with git commits
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
    journal.sh surface-dashboard  # Focus dashboard or open
    journal.sh surface-todo  # Focus TODO list or open
    journal.sh surface-tabs  # Focus frozen tabs (iced) list or open
    journal.sh watchlist update  # Refresh streaming statuses and archive watched items
    journal.sh watchlist suggest 5  # Ask agy for 5 reviewable suggestions
    journal.sh readlist import --audible-html ~/Downloads/Audible\ Library.html
    journal.sh readlist import --fetch-audible-browser --audible-domain www.audible.ca
    journal.sh plan          # Generate daily plan
    journal.sh commits       # Update today's git commit summary
    journal.sh review        # Show outstanding TODOs
    journal.sh index         # Regenerate diary index
    journal.sh weekly        # Generate and open weekly summary
    journal.sh weekly --no-open  # Generate weekly summary without opening Neovim
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
        dashboard)
            cmd_dashboard
            ;;
        surface-dashboard)
            cmd_surface_dashboard
            ;;
        todo)
            cmd_todo
            ;;
        surface-todo)
            cmd_surface_todo
            ;;
        tabs)
            cmd_tabs
            ;;
        surface-tabs)
            cmd_surface_tabs
            ;;
        watchlist)
            shift
            cmd_watchlist "$@"
            ;;
        readlist)
            shift
            cmd_readlist "$@"
            ;;
        plan)
            cmd_plan
            ;;
        commits)
            cmd_commits
            ;;
        review)
            cmd_review
            ;;
        index)
            cmd_index
            ;;
        weekly)
            shift
            cmd_weekly "$@"
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
