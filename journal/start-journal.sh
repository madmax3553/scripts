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
# Script: start-journal.sh
# Purpose: Daily journal helper with window management
# Dependencies: nvim, hyprctl (optional), ghostty/kitty/alacritty (optional)
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

# Daily journal helper. Creates today's entry (if missing), pulls forward
# unchecked tasks from yesterday, and opens/focuses the journal in Neovim.
# Usage:
#   start-journal.sh          # ensure today's file and open (default)
#   start-journal.sh surface  # focus existing journal window or open if absent

JOURNAL_DIR="${JOURNAL_DIR:-${HOME}/projects/journal/diary}"
TERMINAL="${TERMINAL:-ghostty}"
TITLE_PREFIX="${TITLE_PREFIX:-Journal}"
TODAY="$(date +%Y-%m-%d)"
WEEKDAY="$(date +%u)" # 1=Mon ... 7=Sun
IS_WEEKEND=$([[ "${WEEKDAY}" -ge 6 ]] && echo 1 || echo 0)
TITLE="${TITLE_PREFIX} ${TODAY}"
JOURNAL_FILE="${JOURNAL_DIR}/${TODAY}.md"
JUMP_SECTION=""
LOG_FILE="${JOURNAL_LOG_FILE:-${XDG_STATE_HOME:-${HOME}/.local/state}/journal.log}"
FOUND_ADDR=""

log() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  printf '%s %s\n' "$(date +'%F %T')" "$*" >> "${LOG_FILE}"
}

float_and_center() {
  command -v hyprctl >/dev/null 2>&1 || return 0

  local addr floating
  for _ in {1..15}; do
    addr="$(
      hyprctl -j clients | jq -r --arg prefix "${TITLE_PREFIX}" '
        map(select(
          (.title // "" | ascii_downcase | test($prefix|ascii_downcase)) or
          (.initialTitle // "" | ascii_downcase | test($prefix|ascii_downcase))
        )) | map(.address) | first // empty
      '
    )"
    [[ -n "${addr}" ]] && break
    sleep 0.1
  done

  [[ -z "${addr}" ]] && { log "float: no addr found for prefix ${TITLE_PREFIX}"; return 0; }

  floating="$(
    hyprctl -j clients | jq -r --arg addr "${addr}" '
      map(select(.address == $addr)) | .[0].floating // false
    ' 2>/dev/null || echo "false"
  )"

  hyprctl dispatch focuswindow "address:${addr}" >/dev/null 2>&1 || true
  if [[ "${floating}" != "true" ]]; then
    hyprctl dispatch togglefloating "address:${addr}" >/dev/null 2>&1 || true
    log "float: toggled floating for ${addr}"
  fi
  hyprctl dispatch centerwindow "address:${addr}" >/dev/null 2>&1 || true
}

create_template_weekday() {
  mkdir -p "${JOURNAL_DIR}"
  cat > "${JOURNAL_FILE}" <<EOF
# Daily Journal - ${TODAY}

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
}

create_template_weekend() {
  mkdir -p "${JOURNAL_DIR}"
  cat > "${JOURNAL_FILE}" <<EOF
# Weekend Journal - ${TODAY}

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
}

carry_forward_tasks() {
  local yesterday yesterday_file
  yesterday="$(date -d "yesterday" +%Y-%m-%d)"
  yesterday_file="${JOURNAL_DIR}/${yesterday}.md"

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
    log "creating template: weekend=${IS_WEEKEND} file=${JOURNAL_FILE}"
    if [[ "${IS_WEEKEND}" -eq 1 ]]; then
      create_template_weekend
    else
      create_template_weekday
    fi
    carry_forward_tasks
  else
    log "journal exists: ${JOURNAL_FILE}"
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
    log "weekend jump -> ${JUMP_SECTION}"
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
  log "weekday jump -> ${JUMP_SECTION}"
}

focus_existing_window() {
  command -v hyprctl >/dev/null 2>&1 || return 1

  local address
  address="$(
    hyprctl -j clients | jq -r --arg title "${TITLE}" '
      map(select(
        (.title // "" ) == $title or
        (.initialTitle // "" ) == $title
      )) |
      max_by(.pid // 0) | .address // empty
    '
  )"

  if [[ -z "${address}" ]]; then
    log "focus: no matching window found (title=${TITLE})"
    return 1
  fi

  FOUND_ADDR="${address}"
  log "focus: focusing address ${address}"
  hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1 || log "focus: dispatch failed"
  return 0
}

launch_journal() {
  log "launch: opening journal file=${JOURNAL_FILE}"
  setsid xdg-open "${JOURNAL_FILE}" >/dev/null 2>&1 &
}

mode="${1:-open}"
ensure_today
pick_jump_section

case "${mode}" in
  surface)
    FOUND_ADDR="" && focus_existing_window || launch_journal
    ;;
  open|*)
    FOUND_ADDR="" && launch_journal
    ;;
esac
