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
# Script: stfc-launch.sh
# Purpose: Star Trek Fleet Command Wine launcher
# Dependencies: wine, wineserver
# Author: groot
# Modified: 2026-01-24

set -e

# Configuration
WINEPREFIX="/home/groot/Games/stfc-lutris"
# WINE_PATH="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-25/files/bin"
WINE_PATH="/usr/share/steam/compatibilitytools.d/proton-ge-custom/files/bin"
GAME_DIR="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Star Trek Fleet Command"
LAUNCHER_EXE="$GAME_DIR/launcher.exe"

# Export Wine environment
export WINEPREFIX
export PATH="$WINE_PATH:$PATH"
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
export DXVK_HUD=0
export WINEDLLOVERRIDES="version=n,b"

# Kill any existing wineserver
wineserver -k 2>/dev/null || true
sleep 1

# Launch directly with Wine
exec wine "$LAUNCHER_EXE"
