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
# Script: launcher.sh
# Purpose: Launch fuzzel on Wayland or fall back to rofi based on preference and availability
# Dependencies: fuzzel or rofi
# Author: groot

set -euo pipefail

PREF="${LAUNCHER_PREFERENCE:-auto}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

launch_or_die() {
  local cmd="$1"
  shift || true
  if command_exists "$cmd"; then
    exec "$cmd" "$@"
  else
    printf 'launcher: %s requested but not installed.\n' "$cmd" >&2
    exit 1
  fi
}

case "$PREF" in
  fuzzel)
    launch_or_die fuzzel "$@"
    ;;
  rofi)
    launch_or_die rofi "$@"
    ;;
  auto|*)
    if command_exists fuzzel && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
      exec fuzzel "$@"
    elif command_exists rofi; then
      exec rofi "$@"
    elif command_exists fuzzel; then
      exec fuzzel "$@"
    else
      printf 'launcher: install fuzzel or rofi to continue.\n' >&2
      exit 1
    fi
    ;;
esac
