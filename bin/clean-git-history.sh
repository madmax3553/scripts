#!/usr/bin/env bash

# clean-git-history.sh - Purge bloated files/folders from a Git repository's history
# Uses git-filter-repo for safe and fast history rewriting

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

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

REPO_DIR="/home/groot/projects/Chetan_Macros"

# Ensure git-filter-repo is installed
if ! which git-filter-repo &>/dev/null; then
    log_error "git-filter-repo is not installed. Please install it using: pacman -S git-filter-repo"
    exit 1
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
    log_error "Directory $REPO_DIR does not exist or is not a git repository."
    exit 1
fi

cd "$REPO_DIR"

# Check if working directory is clean
if [[ -n "$(git status --porcelain)" ]]; then
    log_error "The repository has uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Get current size
initial_size=$(du -sh .git | cut -f1)
log_info "Initial size of .git folder: ${BOLD}${initial_size}${NC}"

# Get the remote URL so we can restore it later (git-filter-repo removes remotes for safety)
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "git@github.com:madmax3553/Chetan_Macros.git")
log_info "Detected remote URL: $REMOTE_URL"

# Backup the .git folder just in case
BACKUP_PATH="/home/groot/projects/Chetan_Macros_git_backup_$(date +%F_%T | tr : -).tar.gz"
log_info "Backing up original .git directory to $BACKUP_PATH..."
tar -czf "$BACKUP_PATH" .git
log_success "Backup created successfully."

# Purge target folders/files from history
# We target Rust/nov-sourcing/target (bloated build files)
# and Rust/nov-sourcing/data/import/raw (bloated raw data)
log_info "Rewriting Git history to purge bloated files..."
git-filter-repo --force \
    --path Rust/nov-sourcing/target \
    --path Rust/nov-sourcing/data/import/raw \
    --invert-paths

# Restore the remote
log_info "Restoring remote origin..."
git remote add origin "$REMOTE_URL"

# Re-optimize and prune the repo
log_info "Pruning and garbage collecting..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

final_size=$(du -sh .git | cut -f1)
log_success "Cleanup complete!"
log_info "Final size of .git folder: ${BOLD}${final_size}${NC}"
log_warning "Note: Because history was rewritten, your local repository's commits no longer match the remote history."
log_warning "To sync with GitHub, you will need to run: ${BOLD}git push origin --force --all${NC}"
