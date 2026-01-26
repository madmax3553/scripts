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
# Script: phase1-add-error-handling.sh
# Purpose: Apply consistent error handling to Phase 1 scripts
# Dependencies: <fill in as needed>
# Author: Custom
# Modified: 2026-01-24

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
readonly BIN_DIR

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}Adding Error Handling (set -euo pipefail)${RESET}\n"

# These should already have it or are third-party
PRESERVE_SCRIPTS=(
    "powermenu.sh"
    "themeswitcher.sh"
    "scope.sh"
    "bunx"
    "txtcliphist"
)

# Check if script is in preserve list
is_preserved() {
    local script="$1"
    for p in "${PRESERVE_SCRIPTS[@]}"; do
        [[ "$script" == "$p" ]] && return 0
    done
    return 1
}

added=0
skipped=0
already_has=0

for script in "$BIN_DIR"/*.sh "$BIN_DIR"/{update,remote,repostatus,startgp,wiki-*}; do
    [[ ! -f "$script" ]] && continue
    
    name=$(basename "$script")
    
    # Skip third-party and config files
    if is_preserved "$name"; then
        skipped=$((skipped + 1))
        continue
    fi
    
    # Check if already has error handling
    if head -10 "$script" | grep -qE "set -[eo]"; then
        already_has=$((already_has + 1))
        continue
    fi
    
    # Skip files with less than 5 lines or markdown files
    if [[ $(wc -l < "$script") -lt 5 ]]; then
        skipped=$((skipped + 1))
        continue
    fi
    
    # Insert error handling after shebang and comments
    {
        # Print shebang
        head -1 "$script"
        
        # Print comments (up to first blank line or first code)
        skip_lines=1
        while IFS= read -r line; do
            skip_lines=$((skip_lines + 1))
            if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
                echo "$line"
            else
                break
            fi
        done < <(tail -n +2 "$script")
        
        # Add error handling if not already present
        if ! tail -n +2 "$script" | grep -qE "^set -[eo]"; then
            echo ""
            echo "set -euo pipefail"
        fi
        
        # Print rest of file
        tail -n +$skip_lines "$script"
    } > "$script.tmp"
    
    # Only update if file changed
    if ! diff -q "$script" "$script.tmp" >/dev/null 2>&1; then
        mv "$script.tmp" "$script"
        chmod +x "$script"
        echo -e "${GREEN}✓${RESET} Added error handling: $name"
        added=$((added + 1))
    else
        rm "$script.tmp"
    fi
done

echo ""
echo -e "${BLUE}Summary:${RESET}"
echo "Added error handling: $added scripts"
echo "Already had error handling: $already_has scripts"
echo "Skipped (preserved/too small): $skipped scripts"
