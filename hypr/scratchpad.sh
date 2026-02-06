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
# Script: scratchpad.sh
# Purpose: Quick scratchpad note window
# Dependencies: nvim, hyprctl (optional)
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

# Quick scratchpad for jotting. Surfaces existing window if open; otherwise
# opens the scratch file in Neovim inside your terminal.
# Usage:
#   scratchpad.sh          # open
#   scratchpad.sh surface  # focus existing or open

SCRATCH_FILE="${SCRATCH_FILE:-${HOME}/projects/journal/scratch.md}"
TERMINAL="${TERMINAL:-ghostty}"
TITLE_PREFIX="${SCRATCH_TITLE_PREFIX:-Scratchpad}"
TITLE="${TITLE_PREFIX}"
LOG_FILE="${SCRATCH_LOG_FILE:-${XDG_STATE_HOME:-${HOME}/.local/state}/scratchpad.log}"
FOUND_ADDR=""

log() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  printf '%s %s\n' "$(date +'%F %T')" "$*" >> "${LOG_FILE}"
}

float_and_center() {
  command -v hyprctl >/dev/null 2>&1 || return 0

  local hint_addr="${FOUND_ADDR}"
  local addr floating
  if [[ -n "${hint_addr}" ]]; then
    addr="${hint_addr}"
  else
    for _ in {1..25}; do
      addr="$(
        hyprctl -j clients | jq -r --arg title "${TITLE}" '
          map(select(
            (.title // "") == $title or
            (.initialTitle // "") == $title
          )) | max_by(.pid // 0) | .address // empty
        '
      )"
      [[ -n "${addr}" ]] && break
      sleep 0.08
    done
  fi

  [[ -z "${addr}" ]] && { log "float: no addr found for title ${TITLE}"; return 0; }

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
  hyprctl dispatch resizeactive exact 1100 800 >/dev/null 2>&1 || true
}

ensure_file() {
  mkdir -p "$(dirname "${SCRATCH_FILE}")"
  if [[ ! -f "${SCRATCH_FILE}" ]]; then
    printf "# Scratchpad\n\n" > "${SCRATCH_FILE}"
    log "created scratch file ${SCRATCH_FILE}"
  else
    log "scratch exists ${SCRATCH_FILE}"
  fi
}

focus_existing_window() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  local address
  address="$(
    hyprctl -j clients | jq -r --arg title "${TITLE}" '
      map(select(
        (.title // "") == $title or
        (.initialTitle // "") == $title
      )) |
      max_by(.pid // 0) | .address // empty
    '
  )"
  if [[ -z "${address}" ]]; then
    log "focus: no matching scratchpad window"
    return 1
  fi
  FOUND_ADDR="${address}"
  log "focus: focusing address ${address}"
  hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1 || log "focus: dispatch failed"
  return 0
}

launch() {
  local nvim_full=(nvim +set\ notitle "${SCRATCH_FILE}")
  log "launch: terminal=${TERMINAL} title=\"${TITLE}\" file=${SCRATCH_FILE}"
  local cmd=()
  case "${TERMINAL}" in
    ghostty)   cmd=(ghostty --title="${TITLE}" -e "${nvim_full[@]}") ;;
    kitty)     cmd=(kitty --class Scratchpad --title "${TITLE}" "${nvim_full[@]}") ;;
    alacritty) cmd=(alacritty --class Scratchpad --title "${TITLE}" -e "${nvim_full[@]}") ;;
    *)         cmd=("${TERMINAL}" -e "${nvim_full[@]}") ;;
  esac
  setsid "${cmd[@]}" >/dev/null 2>&1 &
  float_and_center
}

mode="${1:-open}"
ensure_file

case "${mode}" in
  surface) FOUND_ADDR="" && focus_existing_window || launch ;;
  *)       FOUND_ADDR="" && launch ;;
esac
