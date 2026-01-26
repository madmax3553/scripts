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
# Script: dotfiles-status.sh
# Purpose: Utility: dotfile   tatu
# Dependencies: <fill in as needed>
# Author: Custom
# Modified: 2026-01-24

set -euo pipefail

DOTFILES_DIR="$HOME/dotfiles"
CONFIG_DIR="$HOME/.config"
IGNORE_FILE="$DOTFILES_DIR/.stowignore"

declare -a STOW_IGNORE=()
if [ -f "$IGNORE_FILE" ]; then
    mapfile -t STOW_IGNORE < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$IGNORE_FILE")
fi

is_ignored() {
    local candidate="$1"
    for ignored in "${STOW_IGNORE[@]}"; do
        if [[ "$candidate" == "$ignored" ]]; then
            return 0
        fi
    done
    return 1
}

section() {
    printf '\n=== %s ===\n' "$1"
}

if [ ! -d "$DOTFILES_DIR" ]; then
    echo "dotfiles directory ($DOTFILES_DIR) not found"
    exit 1
fi

section "Symlinks in ~ pointing to dotfiles"
find "$HOME" -maxdepth 1 -type l -lname 'dotfiles/*' -exec ls -l {} + 2>/dev/null | sort || true

section "Symlinks in ~/.config pointing to dotfiles"
if [ -d "$CONFIG_DIR" ]; then
    find "$CONFIG_DIR" -maxdepth 1 -type l -lname '../dotfiles/*' -exec ls -l {} + 2>/dev/null | sort || true
else
    echo "~/.config not found"
fi

section "Real ~/.config entries (not managed by stow)"
if [ -d "$CONFIG_DIR" ]; then
    mapfile -t config_entries < <(find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 ! -type l -printf '%f\n' | sort)
    for name in "${config_entries[@]}"; do
        key=".config/$name"
        is_ignored "$key" && continue
        printf '  - %s\n' "$name"
    done
fi

section "Root-level dot entries that are regular files/directories"
declare -a root_entries=()
for entry in "$HOME"/.*; do
    name=$(basename "$entry")
    case "$name" in
        .|..|.cache|.config|.local|.mozilla|.steam|.steampath|.steampid|.bun|.cargo|.rustup|.npm|.pki|.gnupg|.mypy_cache|.dotnet)
            continue
            ;;
    esac
    [ ! -e "$entry" ] && continue
    [ -L "$entry" ] && continue
    is_ignored "$name" && continue
    root_entries+=("$name")
done
if [ ${#root_entries[@]} -gt 0 ]; then
    printf '%s\n' "${root_entries[@]}" | sort | sed 's/^/  - /'
fi

section "Available stow packages in $DOTFILES_DIR"
find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.git' -printf '  - %f\n' | sort

if [ ${#STOW_IGNORE[@]} -gt 0 ]; then
    section "Ignored entries (from $IGNORE_FILE)"
    for entry in "${STOW_IGNORE[@]}"; do
        printf '  - %s\n' "$entry"
    done
fi
