#!/usr/bin/env bash

# clean-cache.sh - Reclaim system disk space by cleaning caches and logs
# Safe for run on Arch Linux

set -euo pipefail

# Style definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

DRY_RUN=false
FORCE=false

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Options:
  -d, --dry-run   Show how much space can be reclaimed without deleting files
  -f, --force     Clean files without confirmation prompts
  -h, --help      Show this help message

Cleaned categories:
  - Pacman cache (keeps last 2 versions of installed pkgs)
  - Yay build cache (~/.cache/yay)
  - Systemd Journal logs (limits to 100M)
  - Chrome cache (~/.cache/google-chrome)
  - Qutebrowser cache (~/.cache/qutebrowser)
  - Steam downloading cache (~/.local/share/Steam/steamapps/downloading)
  - Go build cache (~/.cache/go-build)
  - NPM cache (~/.npm/_cacache)
  - Playwright browser cache (~/.cache/ms-playwright)
  - Wallust cache (~/.cache/wallust)
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if we can run sudo commands without prompting or if we have sudo
has_sudo() {
    if [[ "$DRY_RUN" = "true" ]]; then
        return 0
    fi
    if sudo -n true 2>/dev/null; then
        return 0
    else
        log_warning "This action requires sudo. You may be prompted for your password."
        return 1
    fi
}

# Function to calculate directory size
get_size() {
    local path="$1"
    if [[ -e "$path" ]]; then
        local size
        size=$(du -sh "$path" 2>/dev/null | cut -f1 || true)
        if [[ -z "$size" ]]; then
            echo "Permission Denied"
        else
            echo "$size"
        fi
    else
        echo "0B"
    fi
}

confirm() {
    if [[ "$FORCE" = "true" ]]; then
        return 0
    fi
    echo -n -e "${BOLD}$1 [y/N]:${NC} "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    fi
    return 1
}

INITIAL_SPACE=$(df -h / | tail -n 1 | awk '{print $4}')
log_info "Initial free space on root: ${BOLD}${INITIAL_SPACE}${NC}"
echo "--------------------------------------------------"

# Category Definitions
clean_pacman() {
    local size
    size=$(get_size /var/cache/pacman/pkg)
    log_info "Pacman Package Cache: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Clean old pacman package cache (keeps last 2 installed versions)?"; then
        has_sudo || true
        sudo paccache -rk2
        sudo paccache -ruk0
    fi
}

clean_yay() {
    local size
    size=$(get_size "$HOME/.cache/yay")
    log_info "Yay AUR Cache: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Clear yay AUR build files?"; then
        rm -rf "$HOME/.cache/yay"/*
        log_success "Cleared yay cache."
    fi
}

clean_journal() {
    local size
    size=$(get_size /var/log/journal)
    log_info "Systemd Journal Logs: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Vacuum systemd journal logs to 100M?"; then
        has_sudo || true
        sudo journalctl --vacuum-size=100M
    fi
}

clean_steam() {
    local size
    size=$(get_size "$HOME/.local/share/Steam/steamapps/downloading")
    log_info "Steam Temp Downloads: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if [[ "$size" != "0B" ]] && confirm "Clear temporary Steam download files?"; then
        rm -rf "$HOME/.local/share/Steam/steamapps/downloading"/*
        log_success "Cleared Steam download cache."
    fi
}

clean_chrome() {
    local size
    size=$(get_size "$HOME/.cache/google-chrome")
    log_info "Google Chrome Cache: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Clear Google Chrome cache?"; then
        rm -rf "$HOME/.cache/google-chrome"/*
        log_success "Cleared Chrome cache."
    fi
}

clean_qutebrowser() {
    local size
    size=$(get_size "$HOME/.cache/qutebrowser")
    log_info "Qutebrowser Cache: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Clear Qutebrowser cache?"; then
        rm -rf "$HOME/.cache/qutebrowser"/*
        log_success "Cleared Qutebrowser cache."
    fi
}

clean_go() {
    if which go &>/dev/null; then
        local size
        size=$(get_size "$HOME/.cache/go-build")
        log_info "Go Build Cache: $size"
        if [[ "$DRY_RUN" = "true" ]]; then
            return
        fi
        if confirm "Clear Go build cache?"; then
            go clean -cache
            log_success "Cleared Go build cache."
        fi
    fi
}

clean_npm() {
    local size
    size=$(get_size "$HOME/.npm")
    log_info "NPM Cache: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Clear NPM cache?"; then
        npm cache clean --force || rm -rf "$HOME/.npm"/*
        log_success "Cleared NPM cache."
    fi
}

clean_playwright() {
    local size
    size=$(get_size "$HOME/.cache/ms-playwright")
    log_info "Playwright Browsers: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Clear Playwright test browsers?"; then
        rm -rf "$HOME/.cache/ms-playwright"/*
        log_success "Cleared Playwright cache."
    fi
}

clean_wallust() {
    local size
    size=$(get_size "$HOME/.cache/wallust")
    log_info "Wallust Cache: $size"
    if [[ "$DRY_RUN" = "true" ]]; then
        return
    fi
    if confirm "Clear Wallust colorscheme cache?"; then
        rm -rf "$HOME/.cache/wallust"/*
        log_success "Cleared Wallust cache."
    fi
}

# Run cleans
clean_pacman
clean_yay
clean_journal
clean_steam
clean_chrome
clean_qutebrowser
clean_go
clean_npm
clean_playwright
clean_wallust

echo "--------------------------------------------------"
if [[ "$DRY_RUN" = "false" ]]; then
    FINAL_SPACE=$(df -h / | tail -n 1 | awk '{print $4}')
    log_success "Cleanup complete!"
    log_info "Final free space on root: ${BOLD}${FINAL_SPACE}${NC}"
else
    log_info "Dry run finished. No files were modified."
fi
