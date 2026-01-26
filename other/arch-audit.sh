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
# Script: arch-audit.sh
# Purpose: Utility: arc  audit
# Dependencies: <fill in as needed>
# Author: Custom
# Modified: 2026-01-24

set -euo pipefail
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_RED="\e[31m"
STYLE_BOLD="\e[1m"
STYLE_RESET="\e[0m"

# --- Helper Functions ---
print_header() {
    printf "\n${STYLE_BOLD}${COLOR_BLUE}===${STYLE_RESET} ${STYLE_BOLD}%s${STYLE_RESET}\n" "$1"
}

prompt_yes_no() {
    while true; do
        read -p "$(printf "${STYLE_BOLD}${COLOR_YELLOW}:: %s [Y/n] ${STYLE_RESET}" "$1")" yn
        case $yn in
            [Yy]* | "" ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# --- Sudo check: Rerun script with sudo if not root ---
if [ "$EUID" -ne 0 ]; then
  echo "This script needs to run with sudo privileges for pacman operations."
  # Restarting script with sudo
  exec sudo -- "$0" "$@"
fi

# --- 1. Orphan Packages ---
print_header "Checking for Orphaned Packages..."
orphans=$(pacman -Qdtq)

if [ -z "$orphans" ]; then
    printf "${COLOR_GREEN}✔ No orphaned packages found.${STYLE_RESET}\n"
else
    printf "${COLOR_YELLOW}Found orphaned packages. Reviewing individually...${STYLE_RESET}\n"

    # Create an array from the list of orphans
    read -r -a orphan_array <<< "$orphans"

    for i in "${!orphan_array[@]}"; do
        pkg=${orphan_array[$i]}
        printf "\n${STYLE_BOLD}--- Orphan %s of %s: %s ---${STYLE_RESET}\n" "$((i+1))" "${#orphan_array[@]}" "$pkg"
        pacman -Qi "$pkg"
        echo

        while true; do
            read -p "$(printf "${STYLE_BOLD}${COLOR_YELLOW}:: Remove this package? [y/n/a/q] ${STYLE_RESET}")" ynaq
            case $ynaq in
                [Yy]* )
                    pacman -Rns "$pkg"
                    break;;
                [Nn]* )
                    printf "${COLOR_RED}Skipping %s.${STYLE_RESET}\n" "$pkg"
                    break;;
                [Aa]* )
                    printf "${COLOR_YELLOW}Removing all remaining orphans...${STYLE_RESET}\n"
                    # Get all packages from the current one to the end
                    remaining_orphans=("${orphan_array[@]:i}")
                    printf "%s\n" "${remaining_orphans[@]}" | pacman -Rns -
                    printf "${COLOR_GREEN}✔ All remaining orphans removed.${STYLE_RESET}\n"
                    break 2;; # Break out of both the while and for loops
                [Qq]* )
                    printf "${COLOR_RED}Quitting orphan review.${STYLE_RESET}\n"
                    break 2;; # Break out of both the while and for loops
                * ) echo "Please answer y (yes), n (no), a (all), or q (quit).";;
            esac
        done
    done
fi

# --- 2. Package Cache ---
print_header "Checking Package Cache..."
if ! command -v paccache &> /dev/null; then
    printf "${COLOR_RED}Error: paccache command not found.${STYLE_RESET}\n"
    printf "Please install it with: sudo pacman -S pacman-contrib\n"
else
    printf "Current cache size: $(du -sh /var/cache/pacman/pkg/ | awk '{print $1}')\n"
    if prompt_yes_no "Clean cache? (keeps last 2 versions)"; then
        paccache -rk2
        printf "\nRemoving cached versions of uninstalled packages...\n"
        paccache -ruk0
        printf "\n${COLOR_GREEN}✔ Cache cleaned. New size: $(du -sh /var/cache/pacman/pkg/ | awk '{print $1}')${STYLE_RESET}\n"
    else
        printf "${COLOR_RED}Skipping cache cleaning.${STYLE_RESET}\n"
    fi
fi

# --- 3. Explicitly Installed Packages (For Review) ---
print_header "Review Explicitly Installed Packages"
printf "These are packages you installed yourself. Review them to see if you still need them.\n"
printf "Use 'pacman -Qi <package>' to get more info.\n\n"

printf "${STYLE_BOLD}From Official Repositories:${STYLE_RESET}\n"
pacman -Qen | column

printf "\n${STYLE_BOLD}From AUR:${STYLE_RESET}\n"
pacman -Qem | column

# --- 4. Largest Packages (For Review) ---
print_header "Top 20 Largest Installed Packages"
printf "Review this list for large packages you may no longer need.\n\n"
pacman -Qi | awk '/^Name/{name=$3} /^Installed Size/{print $4, $5, name}' | sort -hr | head -n 20 | column -t

print_header "Audit Complete"
