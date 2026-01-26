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
# Script: phase1-apply-standards.sh
# Purpose: Add standard headers and fix shebangs/error handling
# Dependencies: <fill in as needed>
# Author: Custom
# Modified: 2026-01-24

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
readonly BIN_DIR

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}Phase 1 Standards Application${RESET}\n"

# Scripts to process (exclude third-party and documentation)
declare -a SCRIPTS=(
    "PowerManagement.sh"
    "arch-audit.sh"
    "charge-rate.sh"
    "charge-waybar.sh"
    "cliphist-watch.sh"
    "dotfiles-status.sh"
    "fuzzy_finder.sh"
    "install.sh"
    "launcher.sh"
    "launch.sh"
    "monitor.sh"
    "monitor_setup.sh"
    "notifications.sh"
    "oldpaper.sh"
    "power.sh"
    "remote"
    "repostatus"
    "screenshot.sh"
    "scratchpad.sh"
    "start-journal.sh"
    "startgp"
    "stfc-launch.sh"
    "toggle.sh"
    "update"
    "update-mirrors.sh"
    "wallpaper.sh"
    "wallpapermenu.sh"
    "waybar-repostatus.sh"
    "wifi.sh"
    "wifinew.sh"
    "wifistatus.sh"
    "wiki-daily-plan"
    "wiki-helper"
    "wiki-review-todos"
    "window-switcher.sh"
    "yay-waybar.sh"
    "config.sh"
    "scope.sh"
    "dotfiles-status.sh"
)

updated=0
skipped=0

for script in "${SCRIPTS[@]}"; do
    filepath="$BIN_DIR/$script"
    [[ ! -f "$filepath" ]] && continue
    
    # Check if already has Purpose header
    if head -5 "$filepath" | grep -q "^# Purpose:"; then
        skipped=$((skipped + 1))
        continue
    fi
    
    # Extract filename and create purpose from it
    name="$script"
    purpose=$(echo "$name" | sed 's/[-_.sh]/ /g; s/^/Utility: /')
    
    # Get current shebang
    shebang=$(head -1 "$filepath")
    
    # Standardize to #!/usr/bin/env bash if it has a shebang
    if [[ "$shebang" =~ ^#! ]]; then
        new_shebang="#!/usr/bin/env bash"
    else
        new_shebang="#!/usr/bin/env bash"
    fi
    
    # Create temp file with new header
    {
        echo "$new_shebang"
        echo "# $name"
        echo "# Purpose: $purpose"
        echo "# Dependencies: <fill in as needed>"
        echo "# Author: Custom"
        echo "# Modified: $(date +%Y-%m-%d)"
        echo ""
        # Skip old shebang line and output rest
        tail -n +2 "$filepath"
    } > "$filepath.tmp"
    
    mv "$filepath.tmp" "$filepath"
    chmod +x "$filepath"
    echo -e "${GREEN}✓${RESET} Updated: $script"
    updated=$((updated + 1))
done

echo ""
echo -e "${BLUE}Summary:${RESET}"
echo "Updated: $updated scripts"
echo "Skipped (already updated): $skipped scripts"
