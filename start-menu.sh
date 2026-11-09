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
# Script: start-menu.sh
# Purpose: Dashboard/start menu for waybar - launches fuzzel with quick actions
# Dependencies: fuzzel, hyprctl
# Author: groot

set -euo pipefail

entries=(
    "  Apps"
    "  Files"
    "  Terminal"
    "  Browser"
    "󰚩  Ask Antigravity"
    "  Messages"
    "  Clipboard"
    "  Screenshot"
    "󰤆  Power"
    "󰍛  System Monitor"
    "  Journal"
    "󰈐  Dashboard"
    "󰸌  Colorscheme"
    "  Settings"
)

menu=$(printf '%s\n' "${entries[@]}")

chosen=$(echo "$menu" | fuzzel --dmenu \
    --prompt " " \
    --anchor top-left \
    --x-margin 6 \
    --y-margin 38 \
    --width 25 \
    --lines ${#entries[@]} \
    --border-radius 12 \
    --border-width 2) || exit 0

case "$chosen" in
    *Apps)
        ~/.local/bin/launcher/launcher.sh &
        ;;
    *Files)
        dolphin &
        ;;
    *Terminal)
        ghostty &
        ;;
    *Browser)
        qutebrowser &
        ;;
    *Ask\ Antigravity)
        "$HOME/.local/bin/ask-antigravity.sh" &
        ;;
    *Messages)
        ferdium &
        ;;
    *Clipboard)
        "$HOME/.local/bin/txtcliphist" sel 10 &
        ;;
    *Screenshot)
        "$HOME/.local/bin/screenshot.sh" &
        ;;
    *Power)
        "$HOME/.local/bin/wlogout-custom" &
        ;;
    *System\ Monitor)
        ghostty -e btop &
        ;;
    *Journal)
        ~/.local/bin/journal.sh surface &
        ;;
    *Dashboard)
        ~/.local/bin/hypr/dashboard.sh surface &
        ;;
    *Colorscheme)
        "$HOME/.local/bin/system/colorscheme-menu.sh" &
        ;;
    *Settings)
        XDG_CURRENT_DESKTOP=KDE systemsettings &
        ;;
esac
