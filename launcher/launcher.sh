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
# Purpose: Launch fuzzel, the Wayland-native app launcher
# Dependencies: fuzzel
# Author: groot
# Modified: 2026-10-03 - Dropped rofi fallback (binary/config never actually
#           installed on any machine running this repo; fuzzel is the only
#           launcher in active use).

set -euo pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

if command_exists fuzzel; then
  exec fuzzel "$@"
else
  printf 'launcher: install fuzzel to continue.\n' >&2
  exit 1
fi
