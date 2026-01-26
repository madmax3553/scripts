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
# Script: colors.sh
# Purpose: Central location for all ANSI color codes and styles
# Dependencies: <fill in as needed>
# Author: Custom
# Modified: 2026-01-24

# lib/colors.sh - Standardized color and style definitions
# Purpose: Central location for all ANSI color codes and styles
# Usage: source "$(dirname "$0")/lib/colors.sh"

# Text Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export WHITE='\033[0;37m'
export BLACK='\033[0;30m'

# Light/Bright Variants
export LIGHT_RED='\033[1;31m'
export LIGHT_GREEN='\033[1;32m'
export LIGHT_YELLOW='\033[1;33m'
export LIGHT_BLUE='\033[1;34m'
export LIGHT_CYAN='\033[1;36m'
export LIGHT_MAGENTA='\033[1;35m'
export LIGHT_WHITE='\033[1;37m'

# Text Styles
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDERLINE='\033[4m'
export BLINK='\033[5m'
export INVERSE='\033[7m'
export HIDDEN='\033[8m'
export STRIKE='\033[9m'

# Reset
export RESET='\033[0m'
export NC='\033[0m'  # No Color (alias for RESET)

# Common color aliases
export ERROR="${RED}"
export SUCCESS="${GREEN}"
export WARN="${YELLOW}"
export INFO="${BLUE}"
export DEBUG="${CYAN}"

# Style aliases
export HEADER="${BOLD}${BLUE}"
export SECTION="${BOLD}${CYAN}"
export PROMPT="${BOLD}${YELLOW}"
export OK="${GREEN}"
export FAIL="${RED}"
