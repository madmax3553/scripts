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
# Script: logo-colors.sh
# Purpose: Print the Groot logo in selectable ANSI color variants
# Dependencies: none
# Author: groot
# Modified: 2026-01-24

RED='\033[0;31m'
LIGHT_RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
CYAN='\033[0;36m'
LIGHT_CYAN='\033[1;36m'
BLUE='\033[0;34m'
LIGHT_BLUE='\033[1;34m'
MAGENTA='\033[0;35m'
LIGHT_MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Rainbow gradient: Red -> Yellow -> Green -> Cyan -> Blue -> Magenta
print_groot_rainbow() {
    echo -e "${RED}  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓${RESET}"
    echo -e "${LIGHT_RED} ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒${RESET}"
    echo -e "${YELLOW}▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░${RESET}"
    echo -e "${LIGHT_GREEN}░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ ${RESET}"
    echo -e "${GREEN}░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ ${RESET}"
    echo -e "${LIGHT_CYAN} ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   ${RESET}"
    echo -e "${CYAN}  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░    ${RESET}"
    echo -e "${LIGHT_BLUE}░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░      ${RESET}"
    echo -e "${LIGHT_MAGENTA}      ░    ░         ░ ░      ░ ░            ${RESET}"
}

# All Red
print_groot_red() {
    echo -e "${RED}  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓${RESET}"
    echo -e "${RED} ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒${RESET}"
    echo -e "${RED}▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░${RESET}"
    echo -e "${RED}░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ ${RESET}"
    echo -e "${RED}░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ ${RESET}"
    echo -e "${RED} ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   ${RESET}"
    echo -e "${RED}  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░    ${RESET}"
    echo -e "${RED}░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░      ${RESET}"
    echo -e "${RED}      ░    ░         ░ ░      ░ ░            ${RESET}"
}

# All Green
print_groot_green() {
    echo -e "${GREEN}  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓${RESET}"
    echo -e "${GREEN} ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒${RESET}"
    echo -e "${GREEN}▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░${RESET}"
    echo -e "${GREEN}░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ ${RESET}"
    echo -e "${GREEN}░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ ${RESET}"
    echo -e "${GREEN} ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   ${RESET}"
    echo -e "${GREEN}  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░    ${RESET}"
    echo -e "${GREEN}░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░      ${RESET}"
    echo -e "${GREEN}      ░    ░         ░ ░      ░ ░            ${RESET}"
}

# All Blue
print_groot_blue() {
    echo -e "${BLUE}  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓${RESET}"
    echo -e "${BLUE} ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒${RESET}"
    echo -e "${BLUE}▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░${RESET}"
    echo -e "${BLUE}░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ ${RESET}"
    echo -e "${BLUE}░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ ${RESET}"
    echo -e "${BLUE} ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   ${RESET}"
    echo -e "${BLUE}  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░    ${RESET}"
    echo -e "${BLUE}░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░      ${RESET}"
    echo -e "${BLUE}      ░    ░         ░ ░      ░ ░            ${RESET}"
}

# All Cyan
print_groot_cyan() {
    echo -e "${CYAN}  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓${RESET}"
    echo -e "${CYAN} ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒${RESET}"
    echo -e "${CYAN}▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░${RESET}"
    echo -e "${CYAN}░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ ${RESET}"
    echo -e "${CYAN}░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ ${RESET}"
    echo -e "${CYAN} ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   ${RESET}"
    echo -e "${CYAN}  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░    ${RESET}"
    echo -e "${CYAN}░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░      ${RESET}"
    echo -e "${CYAN}      ░    ░         ░ ░      ░ ░            ${RESET}"
}

# All Magenta
print_groot_magenta() {
    echo -e "${MAGENTA}  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓${RESET}"
    echo -e "${MAGENTA} ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒${RESET}"
    echo -e "${MAGENTA}▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░${RESET}"
    echo -e "${MAGENTA}░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ ${RESET}"
    echo -e "${MAGENTA}░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ ${RESET}"
    echo -e "${MAGENTA} ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   ${RESET}"
    echo -e "${MAGENTA}  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░    ${RESET}"
    echo -e "${MAGENTA}░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░      ${RESET}"
    echo -e "${MAGENTA}      ░    ░         ░ ░      ░ ░            ${RESET}"
}

# All White
print_groot_white() {
    echo -e "${WHITE}  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓${RESET}"
    echo -e "${WHITE} ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒${RESET}"
    echo -e "${WHITE}▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░${RESET}"
    echo -e "${WHITE}░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ ${RESET}"
    echo -e "${WHITE}░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ ${RESET}"
    echo -e "${WHITE} ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   ${RESET}"
    echo -e "${WHITE}  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░    ${RESET}"
    echo -e "${WHITE}░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░      ${RESET}"
    echo -e "${WHITE}      ░    ░         ░ ░      ░ ░            ${RESET}"
}

# Usage menu
if [[ $# -eq 0 ]]; then
    echo "GROOT Logo Color Variants"
    echo ""
    echo "Usage: $0 [color]"
    echo ""
    echo "Available colors:"
    echo "  rainbow    - Rainbow gradient (default)"
    echo "  red        - Red color"
    echo "  green      - Green color"
    echo "  blue       - Blue color"
    echo "  cyan       - Cyan color"
    echo "  magenta    - Magenta color"
    echo "  white      - White color"
    echo ""
    echo "Example: $0 rainbow"
    exit 0
fi

case "$1" in
    rainbow)
        print_groot_rainbow
        ;;
    red)
        print_groot_red
        ;;
    green)
        print_groot_green
        ;;
    blue)
        print_groot_blue
        ;;
    cyan)
        print_groot_cyan
        ;;
    magenta)
        print_groot_magenta
        ;;
    white)
        print_groot_white
        ;;
    *)
        echo "Unknown color: $1"
        echo "Use '$0' without arguments to see available colors"
        exit 1
        ;;
esac
