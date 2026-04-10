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
# Script: bin-manager.sh
# Purpose: Central management, tracking, and utilities for script collection
# Dependencies: find, wc
# Author: groot
# Modified: 2025-01-24

set -euo pipefail

readonly BIN_DIR="$HOME/.local/bin"
readonly LIB_DIR="$BIN_DIR/lib"
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bin-manager"

# Colors (inline for independence)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

mkdir -p "$CACHE_DIR"

# Print functions
print_header() {
    printf "\n${BOLD}${BLUE}=== %s ===${RESET}\n" "$1"
}

print_section() {
    printf "\n${BOLD}${CYAN}--- %s ---${RESET}\n" "$1"
}

print_success() {
    printf "${GREEN}✓ %s${RESET}\n" "$1"
}

print_error() {
    printf "${RED}✗ %s${RESET}\n" "$1" >&2
}

print_warn() {
    printf "${YELLOW}⚠ %s${RESET}\n" "$1"
}

# ─────────────────────────────────────────────────────────────────────────────
# List Scripts
# ─────────────────────────────────────────────────────────────────────────────

list_scripts() {
    print_header "Scripts in $BIN_DIR"
    
    local count=0
    local third_party=0
    local custom=0
    
    for script in "$BIN_DIR"/*; do
        [[ ! -f "$script" ]] && continue
        name=$(basename "$script")
        [[ "$name" =~ ^(lib|\.tracking|bin-manager) ]] && continue
        
        size=$(wc -l < "$script")
        shebang=$(head -1 "$script")
        
        # Check for third-party markers
        if head -20 "$script" 2>/dev/null | grep -qE "Author.*:|by |Template"; then
            third_party=$((third_party + 1))
            printf "${CYAN}[THIRD]${RESET} "
        else
            custom=$((custom + 1))
            printf "${GREEN}[CUSTOM]${RESET} "
        fi
        
        printf "%-30s %5d LOC  %s\n" "$name" "$size" "$shebang"
        count=$((count + 1))
    done
    
    print_section "Summary"
    echo "Total scripts: $count"
    echo "  Custom: $custom ($(( custom * 100 / count ))%)"
    echo "  Third-party: $third_party ($(( third_party * 100 / count ))%)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Health Check
# ─────────────────────────────────────────────────────────────────────────────

check_scripts() {
    print_header "Script Health Check"
    
    local issues=0
    local scripts=0
    
    for script in "$BIN_DIR"/*; do
        [[ ! -f "$script" ]] && continue
        name=$(basename "$script")
        [[ "$name" =~ ^(lib|\.tracking|bin-manager) ]] && continue
        
        scripts=$((scripts + 1))
        local errors=0
        
        # Check shebang
        shebang=$(head -1 "$script")
        if ! [[ "$shebang" =~ ^#! ]]; then
            errors=$((errors + 1))
        fi
        
        # Check for set -euo pipefail
        if ! head -20 "$script" 2>/dev/null | grep -qE "set -[eo]"; then
            errors=$((errors + 1))
        fi
        
        if [[ $errors -gt 0 ]]; then
            issues=$((issues + 1))
            printf "${YELLOW}⚠${RESET}  %-30s %d issues\n" "$name" "$errors"
        else
            printf "${GREEN}✓${RESET}  %-30s OK\n" "$name"
        fi
    done
    
    print_section "Summary"
    echo "Scripts checked: $scripts"
    echo "Scripts with issues: $issues"
    if [[ $scripts -gt 0 ]]; then
        echo "Health: $(( (scripts - issues) * 100 / scripts ))%"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase Status
# ─────────────────────────────────────────────────────────────────────────────

show_phase_status() {
    print_header "Phase 1 Implementation Status"
    
    local completed=0
    local total=5
    
    echo ""
    
    # Check lib/colors.sh
    if [[ -f "$LIB_DIR/colors.sh" ]]; then
        print_success "lib/colors.sh created"
        completed=$((completed + 1))
    else
        print_error "lib/colors.sh missing"
    fi
    
    # Check lib/common.sh
    if [[ -f "$LIB_DIR/common.sh" ]]; then
        print_success "lib/common.sh created"
        completed=$((completed + 1))
    else
        print_error "lib/common.sh missing"
    fi
    
    # Check for standard headers
    headers=$(grep -l "^# Purpose:" "$BIN_DIR"/*.sh 2>/dev/null | wc -l)
    if [[ $headers -gt 30 ]]; then
        print_success "Standard headers applied ($(( headers * 100 / 35 ))%)"
        completed=$((completed + 1))
    else
        print_warn "Standard headers: $headers/35 scripts"
    fi
    
    # Check shebang consistency
    env_bash=$(grep -l "^#!/usr/bin/env bash" "$BIN_DIR"/*.sh 2>/dev/null | wc -l)
    if [[ $env_bash -gt 30 ]]; then
        print_success "Shebang standardized ($(( env_bash * 100 / 35 ))%)"
        completed=$((completed + 1))
    else
        print_warn "Shebang standardization: $env_bash/35 scripts"
    fi
    
    # Check error handling
    error_handling=$(grep -l "set -[eo]" "$BIN_DIR"/*.sh 2>/dev/null | wc -l)
    if [[ $error_handling -gt 30 ]]; then
        print_success "Error handling applied ($(( error_handling * 100 / 35 ))%)"
        completed=$((completed + 1))
    else
        print_warn "Error handling: $error_handling/35 scripts"
    fi
    
    print_section "Progress"
    echo "Completed: $completed/$total tasks"
    echo "Progress: $(( completed * 100 / total ))%"
}

# ─────────────────────────────────────────────────────────────────────────────
# Statistics
# ─────────────────────────────────────────────────────────────────────────────

show_statistics() {
    print_header "Script Collection Statistics"
    
    local total_lines=0
    local largest_script=""
    local largest_size=0
    local total_scripts=0
    
    for script in "$BIN_DIR"/*; do
        [[ ! -f "$script" ]] && continue
        name=$(basename "$script")
        [[ "$name" =~ ^(lib|\.tracking|bin-manager) ]] && continue
        
        size=$(wc -l < "$script")
        total_lines=$((total_lines + size))
        total_scripts=$((total_scripts + 1))
        
        if [[ $size -gt $largest_size ]]; then
            largest_size=$size
            largest_script="$name"
        fi
    done
    
    echo ""
    echo "Total scripts: $total_scripts"
    echo "Total lines of code: $total_lines"
    if [[ $total_scripts -gt 0 ]]; then
        echo "Average lines per script: $(( total_lines / total_scripts ))"
    fi
    echo ""
    echo "Largest script: $largest_script ($largest_size LOC)"
    echo ""
    
    print_section "Top 10 Scripts by Size"
    find "$BIN_DIR" -maxdepth 1 -type f ! -name ".*" ! -name "bin-manager.sh" 2>/dev/null | while read -r script; do
        name=$(basename "$script")
        [[ "$name" =~ ^lib ]] && continue
        echo "$(wc -l < "$script") $name"
    done | sort -rn | head -10 | awk '{printf "%4d LOC  %-30s\n", $1, $2}'
}

# ─────────────────────────────────────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
${BOLD}${BLUE}bin-manager.sh${RESET} - Script collection management

${BOLD}${CYAN}Usage:${RESET}
  $(basename "$0") [command]

${BOLD}${CYAN}Commands:${RESET}
  list              List all scripts with metadata
  health            Check script health (shebangs, error handling)
  status            Show Phase 1 implementation status
  stats             Show collection statistics
  help              Show this help message

${BOLD}${CYAN}Examples:${RESET}
  $(basename "$0") list           # List all scripts
  $(basename "$0") health         # Check for style issues
  $(basename "$0") status         # Track Phase 1 progress
  $(basename "$0") stats          # View statistics

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    local command="${1:-list}"
    
    case "$command" in
        list)
            list_scripts
            ;;
        health)
            check_scripts
            ;;
        status)
            show_phase_status
            ;;
        stats)
            show_statistics
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
