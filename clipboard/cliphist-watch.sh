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
# Script: cliphist-watch.sh
# Purpose: Start clipboard history watchers
# Dependencies: wl-clipboard, cliphist
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist"
watch_text_match="wl-paste --type text --watch ${script_dir}/txtcliphist out"

# Avoid duplicate watchers.
if pgrep -f "$watch_text_match" >/dev/null 2>&1; then
  exit 0
fi

$([ -e "$cache_dir" ] && [ ! -d "$cache_dir" ]) && mv "$cache_dir" "${cache_dir}.bak.$(date +%s)"
mkdir -p "$cache_dir"

env CLIPHIST_WATCH=1 wl-paste --type text --watch "${script_dir}/txtcliphist" out &
env CLIPHIST_WATCH=1 wl-paste --type image --watch "${script_dir}/txtcliphist" out &

wait -n
