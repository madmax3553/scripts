#!/usr/bin/env bash
# lock.sh — blur the current wallpaper and invoke swaylock

set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lock"
BLUR_IMG="$CACHE_DIR/blur.png"

mkdir -p "$CACHE_DIR"

# Get current wallpaper path from awww
get_wallpaper() {
    awww query 2>/dev/null \
        | grep -oP 'image: \K[^\s]+' \
        | head -1
}

# Build a blurred version of the wallpaper for the lock screen background.
# Falls back to a plain dark color if no wallpaper or convert is unavailable.
build_blur() {
    local wp
    wp=$(get_wallpaper) || true

    if [[ -n "$wp" && -f "$wp" ]] && command -v magick >/dev/null 2>&1; then
        magick "$wp" -scale 10% -scale 1000% -blur 0x8 "$BLUR_IMG" 2>/dev/null && return 0
    fi
    return 1
}

build_blur && IMG_ARGS=("--image" "$BLUR_IMG" "--scaling" "fill") \
           || IMG_ARGS=("--color" "0d0d0d")

exec swaylock \
    --daemonize \
    --show-failed-attempts \
    --ignore-empty-password \
    --indicator-caps-lock \
    "${IMG_ARGS[@]}" \
    --inside-color 00000088 \
    --ring-color 33ccffcc \
    --key-hl-color 00ff99ff \
    --bs-hl-color ff6633ff \
    --ring-ver-color 33ccffff \
    --ring-wrong-color ff0066ff \
    --line-color 00000000 \
    --separator-color 00000000 \
    --text-color ffffffff \
    --font "Monospace"
