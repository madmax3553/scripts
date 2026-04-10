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
# Script: install.sh
# Purpose: Tuigreet neon theme installer
# Dependencies: greetd, tuigreet
# Author: groot
# Modified: 2026-01-24

set -e

GREETD_CONFIG="/etc/greetd/config.toml"
SOURCE_CONFIG="$(dirname "$0")/config.toml"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   TUIGREET NEON INSTALLER                                ║"
echo "╚══════════════════════════════════════════════════════════╝"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "⚠ This script must be run as root (use sudo)"
   exit 1
fi

# Check dependencies
if ! command -v tuigreet &> /dev/null; then
    echo "✗ tuigreet not found, please install greetd-tuigreet"
    exit 1
fi

if ! command -v greetd &> /dev/null; then
    echo "✗ greetd not found, please install greetd"
    exit 1
fi

# Backup existing config
if [[ -f "$GREETD_CONFIG" ]]; then
    BACKUP="${GREETD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "→ Backing up existing config to $BACKUP"
    cp "$GREETD_CONFIG" "$BACKUP"
fi

# Install new config
echo "→ Installing tuigreet neon config..."
cp "$SOURCE_CONFIG" "$GREETD_CONFIG"
chmod 644 "$GREETD_CONFIG"

# Ensure cache directory exists
if [[ ! -d /var/cache/tuigreet ]]; then
    echo "→ Creating tuigreet cache directory..."
    mkdir -p /var/cache/tuigreet
    chown greeter:greeter /var/cache/tuigreet
    chmod 0755 /var/cache/tuigreet
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✓ Installation complete!"
echo ""
echo "Available sessions:"
echo "  Wayland: /usr/share/wayland-sessions"
for f in /usr/share/wayland-sessions/*.desktop; do
    [[ -f "$f" ]] && echo "    - $(basename "$f" .desktop)"
done
echo "  X11: /usr/share/xsessions"
for f in /usr/share/xsessions/*.desktop; do
    [[ -f "$f" ]] && echo "    - $(basename "$f" .desktop)"
done
echo ""
echo "To switch from SDDM to greetd:"
echo "  sudo systemctl disable sddm"
echo "  sudo systemctl enable greetd"
echo "  sudo systemctl start greetd"
echo "════════════════════════════════════════════════════════════"
