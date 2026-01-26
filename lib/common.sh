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
# Script: common.sh
# Purpose: Shared functionality across scripts
# Dependencies: <fill in as needed>
# Author: Custom
# Modified: 2026-01-24

# lib/common.sh - Common utilities for error handling, logging, and functions
# Purpose: Shared functionality across scripts
# Usage: source "$(dirname "$0")/lib/common.sh"

# Source colors from same directory using BASH_SOURCE for proper path resolution
source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

# Script constants (set by sourcing script)
: "${SCRIPT_NAME:=$(basename "${BASH_SOURCE[-1]}")}"
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[-1]}")/.." && pwd)}"

# Logging configuration
: "${LOG_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/bin-logs}"
: "${LOG_FILE:=$LOG_DIR/$SCRIPT_NAME.log}"
: "${LOG_LEVEL:=INFO}"  # DEBUG, INFO, WARN, ERROR

# Create log directory if needed
mkdir -p "$LOG_DIR" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# Logging Functions
# ─────────────────────────────────────────────────────────────────────────────

log_timestamp() {
    date +'%Y-%m-%d %H:%M:%S'
}

log_debug() {
    [[ "$LOG_LEVEL" != "DEBUG" ]] && return 0
    echo "[$(log_timestamp)] DEBUG: $*" | tee -a "$LOG_FILE" >&2
}

log_info() {
    echo "[$(log_timestamp)] INFO: $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(log_timestamp)] ${WARN}WARN${RESET}: $*" | tee -a "$LOG_FILE" >&2
}

log_error() {
    echo "[$(log_timestamp)] ${ERROR}ERROR${RESET}: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(log_timestamp)] ${SUCCESS}SUCCESS${RESET}: $*" | tee -a "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Output Functions
# ─────────────────────────────────────────────────────────────────────────────

print_header() {
    printf "\n${HEADER}=== %s ===${RESET}\n" "$1"
}

print_section() {
    printf "\n${SECTION}─── %s ───${RESET}\n" "$1"
}

print_error() {
    printf "${ERROR}✗ %s${RESET}\n" "$1" >&2
}

print_success() {
    printf "${SUCCESS}✓ %s${RESET}\n" "$1"
}

print_info() {
    printf "${INFO}ℹ %s${RESET}\n" "$1"
}

print_warn() {
    printf "${WARN}⚠ %s${RESET}\n" "$1"
}

# ─────────────────────────────────────────────────────────────────────────────
# Error Handling
# ─────────────────────────────────────────────────────────────────────────────

die() {
    local msg="${1:-Unknown error}"
    local code="${2:-1}"
    print_error "$msg"
    exit "$code"
}

require_command() {
    if ! command -v "$1" &>/dev/null; then
        die "Required command not found: $1" 1
    fi
}

require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Required commands not found: ${missing[*]}" 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Prompts
# ─────────────────────────────────────────────────────────────────────────────

prompt_yes_no() {
    local msg="${1:-Continue?}"
    local response
    while true; do
        read -r -p "$(printf "${PROMPT}:: %s [y/n] ${RESET}" "$msg")" response
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) print_warn "Please answer yes or no" ;;
        esac
    done
}

prompt_input() {
    local msg="${1:-Enter value}"
    local var_name="${2:-}"
    local response
    read -r -p "$(printf "${PROMPT}:: %s: ${RESET}" "$msg")" response
    if [[ -n "$var_name" ]]; then
        eval "$var_name='$response'"
    else
        echo "$response"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# File Operations
# ─────────────────────────────────────────────────────────────────────────────

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "Failed to create directory: $dir"
        log_debug "Created directory: $dir"
    fi
}

ensure_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        touch "$file" || die "Failed to create file: $file"
        log_debug "Created file: $file"
    fi
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup" || die "Failed to backup file: $file"
        log_info "Backed up: $file → $backup"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Process Management
# ─────────────────────────────────────────────────────────────────────────────

ensure_not_running() {
    local script_name="$1"
    if pgrep -f "$script_name" >/dev/null 2>&1; then
        # Don't count current process
        local count=$(pgrep -f "$script_name" | wc -l)
        if [[ $count -gt 1 ]]; then
            die "Script already running: $script_name"
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
    local code=$?
    log_debug "Cleaning up (exit code: $code)"
    return $code
}

trap cleanup EXIT
