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
# Script: fuzzy_finder.sh
# Purpose: Search installed applications and indexed files from a single launcher surface
# Dependencies: rg, tofi, gtk-launch, xdg-open, sed, stat
# Author: groot

set -euo pipefail

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
file_cache="${cache_dir}/spotlight_files"
lock_dir="${cache_dir}/spotlight_files.lock"
max_age_seconds=600

mkdir -p "$cache_dir"

build_file_cache() {
    rg --files \
        --glob '!**/.git/**' \
        --glob '!**/.cache/**' \
        --glob '!**/node_modules/**' \
        --glob '!**/target/**' \
        --glob '!**/build/**' \
        --glob '!**/vendor/**' \
        "$HOME" >"$file_cache"
}

if [ ! -s "$file_cache" ]; then
    build_file_cache
else
    now_epoch=$(date +%s)
    cache_mtime=$(stat -c %Y "$file_cache")
    cache_age=$((now_epoch - cache_mtime))
    if [ "$cache_age" -gt "$max_age_seconds" ] && mkdir "$lock_dir" 2>/dev/null; then
        (
            build_file_cache
            rmdir "$lock_dir"
        ) >/dev/null 2>&1 &
    fi
fi

list_apps() {
    local app_dir desktop_file name id
    for app_dir in /usr/share/applications "$HOME/.local/share/applications"; do
        [ -d "$app_dir" ] || continue
        while IFS= read -r desktop_file; do
            rg -q '^NoDisplay=true' "$desktop_file" && continue
            rg -q '^Hidden=true' "$desktop_file" && continue
            name=$(rg -m1 '^Name=' "$desktop_file" | cut -d= -f2-)
            [ -n "$name" ] || continue
            id=$(basename "$desktop_file" .desktop)
            printf 'app: %s [%s]\n' "$name" "$id"
        done < <(rg --files -g '*.desktop' "$app_dir")
    done
}

selection=$(
    {
        list_apps
        sed 's|^|file: |' "$file_cache"
    } | tofi
)

[ -n "$selection" ] || exit 0

if [[ "$selection" == app:* ]]; then
    app_id="${selection##*[}"
    app_id="${app_id%]}"
    if [ -n "$app_id" ]; then
        gtk-launch "$app_id"
    fi
elif [[ "$selection" == file:* ]]; then
    file_path="${selection#file: }"
    if [ -n "$file_path" ]; then
        xdg-open "$file_path"
    fi
fi
