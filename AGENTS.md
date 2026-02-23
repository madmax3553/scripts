# AGENTS.md - Bash Scripts Repository Guide

This document helps agents understand how to work effectively in this bash scripts repository.

## Repository Overview

This is a **bash script collection** organized by functionality. All scripts are personal utilities for Linux desktop/system management (Hyprland, Waybar, systemd, etc.).

- **Type**: Bash scripts (no compilation, testing framework, or package manager)
- **Bash Version**: 4.0+ required
- **Platform**: Linux (Arch-based assumed from references to `yay`, `pacman`)
- **Architecture**: Scripts source from absolute paths; deployed via GNU Stow symlinks to `~/.local/bin/`

## Directory Structure

```
scripts/
├── lib/                 # Shared libraries - source these, don't modify structure
│   ├── colors.sh       # ANSI color codes and semantic aliases
│   ├── common.sh       # Logging, error handling, utility functions
│   └── waybar-cache.sh # Caching for Waybar status modules
├── waybar/             # Waybar status bar modules (output JSON for Waybar)
├── hypr/               # Hyprland window manager utilities
├── system/             # System/desktop utilities
├── journal/            # Note-taking and TODO management
├── launcher/           # Application launchers
├── clipboard/          # Clipboard utilities
├── other/              # Miscellaneous utilities
└── archive/            # Deprecated scripts (do not modify)
```

## Code Organization & Patterns

### Script Header Pattern

Every script starts with:
1. Shebang: `#!/usr/bin/env bash`
2. ASCII art logo (from `colors.sh`)
3. Metadata comment block:
   ```bash
   # Script: <filename>
   # Purpose: <description>
   # Dependencies: <commands/tools needed>
   # Author: groot
   # Modified: <date>
   ```
4. `set -euo pipefail` for error handling (in most scripts)

### Sourcing Libraries

Scripts source libraries using **absolute paths** from the deployment location:

```bash
source "/home/groot/projects/scripts/lib/colors.sh"
source "/home/groot/projects/scripts/lib/common.sh"
```

Use absolute paths, not relative (`dirname` tricks for deployment-time handling only).

### Library Functions

#### **colors.sh**
Provides ANSI color codes and semantic aliases. Use these for consistent terminal output.

**Text Colors**: `$RED`, `$GREEN`, `$YELLOW`, `$BLUE`, `$CYAN`, `$MAGENTA`, `$WHITE`, `$BLACK`

**Bright Variants**: `$LIGHT_RED`, `$LIGHT_GREEN`, etc.

**Styles**: `$BOLD`, `$DIM`, `$ITALIC`, `$UNDERLINE`, `$BLINK`, `$INVERSE`, `$HIDDEN`, `$STRIKE`, `$RESET`

**Semantic Aliases** (preferred):
- `$ERROR` (red), `$SUCCESS` (green), `$WARN` (yellow), `$INFO` (blue), `$DEBUG` (cyan)
- `$HEADER`, `$SECTION`, `$PROMPT` (bold variants)
- `$OK`, `$FAIL`

#### **common.sh**
Logging, output formatting, error handling, file operations, process management.

**Logging Functions** (write to `$LOG_FILE` in `~/.cache/bin-logs/`):
- `log_debug`, `log_info`, `log_warn`, `log_error`, `log_success`
- Configurable via `$LOG_LEVEL` (DEBUG, INFO, WARN, ERROR)

**Output Functions** (formatted terminal output):
- `print_header "Title"` - bold blue header
- `print_section "Title"` - bold cyan section
- `print_error "msg"` (✗), `print_success "msg"` (✓), `print_info "msg"` (ℹ), `print_warn "msg"` (⚠)

**Error Handling**:
- `die "message" [exit_code]` - print error and exit
- `require_command cmd` - check if command exists, die if not
- `require_commands cmd1 cmd2 ...` - check multiple commands
- `trap cleanup EXIT` - automatic cleanup (already in common.sh)

**File Operations**:
- `ensure_dir path` - create directory if missing
- `ensure_file path` - create empty file if missing
- `backup_file path` - create timestamped backup

**Process Management**:
- `ensure_not_running script_name` - check if script already running (prevents concurrent runs)

**Prompts**:
- `prompt_yes_no "message"` - interactive yes/no prompt
- `prompt_input "message" [var_name]` - read user input, optionally store in variable

#### **waybar-cache.sh**
Caching system for Waybar modules. Stores JSON output, handles staleness, background updates.

**Core Functions**:
- `cache_serve name command [threshold] [default_output]` - Main function: serve cached data or trigger background update
- `cache_read name` - Read cache file (JSON)
- `cache_write name content` - Write cache file
- `cache_is_stale file [threshold]` - Check if cache older than threshold (seconds, default 300)
- `cache_update_with_lock name cmd` - Run command, update cache, use file lock
- `cache_update_background name cmd` - Run command in background, update cache

**Waybar Output**:
- `waybar_output text [tooltip] [class]` - Generate JSON output for Waybar (use jq if available)

**Configuration** (environment variables):
- `$WAYBAR_CACHE_DIR` - Cache directory (default `~/.cache/waybar`)
- `$WAYBAR_STALE_THRESHOLD` - Staleness threshold in seconds (default 300)
- `$WAYBAR_CACHE_DEBUG` - Set to 1 to enable debug logging

### Waybar Modules

Scripts in `waybar/` output JSON to be displayed by Waybar status bar.

**Pattern**:
1. Source `waybar-cache.sh`
2. Use `cache_serve` to manage cached data
3. Call `waybar_output text tooltip class` to generate JSON
4. Exit with code 0 (Waybar handles errors gracefully)

**Example** (`charge-waybar.sh`):
```bash
source "/home/groot/projects/scripts/lib/waybar-cache.sh"
# ... run command to get data ...
waybar_output "12W" "Charging 85%" "charging"
```

## Code Style & Conventions

### Naming
- **Files**: lowercase with hyphens (`charge-rate.sh`, not `chargeRate.sh`)
- **Variables**: `UPPERCASE` for constants/exports, `lowercase` for locals
- **Functions**: `snake_case`
- **Script names**: lowercase, dash-separated (e.g., `start-journal.sh`)

### Quoting & Variables
- Always quote variables: `"$var"` not `$var`
- Use `${var}` when adjacent to text: `echo "${var}text"`
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `(( ))` for arithmetic

### Error Handling
- Always use `set -euo pipefail` at top of script
- Check command existence before use: `require_command cmd`
- Exit with meaningful codes (0 = success, 1 = error)
- Log errors before exiting: `log_error "msg" && die "msg"`

### Comments
- Use `# ─────────────────────────────────────────────────────` section dividers
- Comment **why**, not what (code shows what)
- Use inline comments sparingly (clear code is self-documenting)

### Spacing & Formatting
- Use 4-space indentation (not tabs)
- Put opening brace on same line: `if condition; then`
- Blank line between function definitions
- Max line length ~100 characters (readability)

### Command-Line Arguments
Use `getopts` for flag parsing. Standard flags:
- `-h` / `--help`: Show usage
- `-i` / `--interval`: Time interval
- `-c` / `--count`: Sample count
- `-j` / `--json`: JSON output format
- `-v` / `--verbose`: Verbose logging

**Pattern**:
```bash
usage() { cat <<EOF
Usage: $(basename "$0") [-h] [-i interval] [-c count] [-j]
  -h            Show this help
  -i interval   Set interval in seconds
  -c count      Number of samples
  -j            JSON output
EOF
}

while getopts "i:c:jh" opt; do
  case $opt in
    i) interval=$OPTARG ;;
    c) count=$OPTARG ;;
    j) json=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done
```

## Important Patterns & Gotchas

### 1. Absolute Path Sourcing
Scripts use **absolute paths** when sourcing libraries, not relative paths:

```bash
# ✓ Correct
source "/home/groot/projects/scripts/lib/colors.sh"

# ✗ Wrong
source "$(dirname "$0")/lib/colors.sh"  # Only in lib files
```

This is because scripts are deployed to `~/.local/bin/` via Stow symlinks, so relative paths break.

### 2. `BASH_SOURCE` vs `$0`
In sourced files, use `${BASH_SOURCE[0]}` to get the sourcing script's path:
- `${BASH_SOURCE[-1]}` = currently sourced file
- `$0` = original script name (unreliable for sourced files)

### 3. Configuration Files
Some scripts load optional config files (e.g., `journal.sh` loads `~/projects/journal/config/journal.conf`):

```bash
CONFIG_FILE="${CONFIG_DIR}/script.conf"
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
fi

# Set defaults if config not loaded
: "${VARIABLE:=default_value}"
```

### 4. JSON Output & jq
Many scripts output JSON for Waybar. Always check if `jq` is installed:

```bash
if ! command -v jq >/dev/null 2>&1; then
    waybar_output "error" "jq not installed" "error"
    exit 0
fi
```

Waybar tolerates graceful failures (missing data, etc.) - exit with 0, not 1.

### 5. Logging Configuration
Scripts auto-create `~/.cache/bin-logs/` directory. Log file: `~/.cache/bin-logs/{script_name}.log`

- `LOG_LEVEL` can be overridden: `LOG_LEVEL=DEBUG my-script.sh`
- Log functions handle color/timestamp automatically
- Always use logging functions, not `echo` for important messages

### 6. Lock Files for Concurrent Prevention
Use `ensure_not_running` to prevent multiple instances:

```bash
source "/home/groot/projects/scripts/lib/common.sh"
ensure_not_running "$(basename "$0")"  # Dies if already running
```

Or use `cache_lock_acquire` for Waybar modules (prevents parallel updates).

### 7. Signals & Cleanup
`common.sh` installs trap handler for `EXIT`:

```bash
trap cleanup EXIT
```

Define custom cleanup if needed:
```bash
cleanup() {
    local code=$?
    # custom cleanup here
    return $code
}
trap cleanup EXIT
```

### 8. XDG Directories
Use standard XDG variables for file paths:
- `$XDG_CACHE_HOME` (default `~/.cache`)
- `$XDG_CONFIG_HOME` (default `~/.config`)
- `$XDG_STATE_HOME` (default `~/.local/state`)
- Fall back to `$HOME` if not set

Example:
```bash
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bin-logs"
```

### 9. Date Handling
Use `date` command with ISO format:

```bash
TODAY="$(date +%Y-%m-%d)"           # 2026-02-22
TIMESTAMP="$(date -Iseconds)"       # ISO with time
WEEKDAY="$(date +%u)"                # 1=Mon ... 7=Sun
YESTERDAY="$(date -d "yesterday" +%Y-%m-%d)"
```

### 10. Hyprland Integration
Scripts communicate with Hyprland window manager via `hyprctl`:

```bash
hyprctl monitors              # List monitors
hyprctl dispatch ...          # Send command to Hyprland
hyprctl --batch ...          # Batch multiple commands
```

Always capture output and check exit codes:
```bash
if monitors=$(hyprctl monitors 2>/dev/null); then
    # Process $monitors
else
    log_error "Failed to get Hyprland monitors"
fi
```

### 11. Stow Symlink Architecture
Scripts deployed like:
```
~/.local/bin/script              (user accesses here)
  → (Stow symlink)
~/dotfiles/bin/.local/bin/script (intermediate symlink)
  → (relative symlink)
~/projects/scripts/.../script    (source of truth - here)
```

So scripts live in `/home/groot/projects/scripts/` but execute from `~/.local/bin/`.

## Key Gotchas

1. **Don't use relative paths for sourcing** - scripts aren't in their deployment location when sourced
2. **Always quote variables** - unquoted `$var` breaks with spaces
3. **Check for required commands early** - use `require_command` or `require_commands`
4. **Waybar modules exit 0 on error** - don't exit 1, show error in output
5. **Cache files use JSON** - even if simple text, Waybar expects valid JSON
6. **Log files auto-created** - no need to check, `common.sh` handles it
7. **Never modify archive/** - keep old versions for reference only
8. **Colors require escape sequences** - test in terminal, may not display in logs
9. **Hyprland commands fail on non-Wayland** - check exit code, don't assume success
10. **XDG directories might not exist** - use `ensure_dir` or `mkdir -p`

## Adding New Scripts

1. Create file in appropriate category directory
2. Add shebang + metadata header
3. `chmod +x script.sh`
4. Source libraries using absolute paths: `source "/home/groot/projects/scripts/lib/colors.sh"`
5. Use `set -euo pipefail` for error safety
6. Call `require_commands` to check dependencies
7. Use logging functions from `common.sh` (or `waybar-cache.sh` for Waybar modules)
8. Test locally in `scripts/` directory
9. Commit to git

## Example Script Template

```bash
#!/usr/bin/env bash
#  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓
# ... (ASCII art optional but consistent)
# Script: my-script.sh
# Purpose: What this does
# Dependencies: cmd1, cmd2, cmd3
# Author: groot
# Modified: 2026-02-22

set -euo pipefail

source "/home/groot/projects/scripts/lib/colors.sh"
source "/home/groot/projects/scripts/lib/common.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

MY_VAR="${MY_VAR:-default_value}"

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────

do_something() {
    local arg="$1"
    log_info "Doing something with: $arg"
    print_success "Done"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

require_commands "cmd1" "cmd2"

print_header "My Script"
do_something "test"

log_success "Script completed successfully"
```

## Testing & Validation

Scripts are not formally tested (no test framework in repo). Instead:
- Execute locally in `scripts/` directory
- Verify output visually
- Check logs in `~/.cache/bin-logs/{script}.log`
- For Waybar modules: test output with `jq` validation

Example:
```bash
./system/charge-rate.sh -j | jq .          # Validate JSON
LOG_LEVEL=DEBUG ./journal/journal.sh        # Enable debug logging
```

## Deployment

Scripts are deployed via GNU Stow:
1. Edit script in `~/projects/scripts/`
2. Commit to git
3. Stow creates symlinks automatically: `stow --dir ~/projects scripts --target ~/.local/bin`
4. Scripts accessible at `~/.local/bin/{category}/{script}`

(User typically runs Stow as part of dotfiles setup, agents don't need to worry about this.)

## Git Workflow

- Repository: `/home/groot/projects/scripts`
- Branch: `master` (single-branch repo)
- Commit messages: Descriptive (e.g., "Add error handling to journal notifications")
- No CI/CD - manual testing before commit

Example commit:
```bash
git add waybar/my-new-module.sh
git commit -m "Add new Waybar module for system status"
```

## Common Commands

```bash
# Run a script with debug logging
LOG_LEVEL=DEBUG ./system/charge-rate.sh

# Check logs
tail -f ~/.cache/bin-logs/{script}.log

# Validate JSON output
./waybar/charge-waybar.sh | jq .

# List all scripts
find . -name "*.sh" -type f | sort

# Check for undefined dependencies
grep -h "require_command\|require_commands" **/*.sh | sort | uniq
```

## Environment

- **Bash**: 4.0+
- **OS**: Linux (Arch-based typical, but POSIX-compatible scripts)
- **Key Tools**: `jq`, `flock`, `pgrep`, `hyprctl`, `nmcli`, `tofi`, `fzf`, `upower`
- **Default User**: `/home/groot` (update script paths if different user)

## Useful References

- [Bash Manual](https://www.gnu.org/software/bash/manual/)
- [ShellCheck](https://www.shellcheck.net/) - Bash linter (not enforced, but useful)
- [POSIX Specification](https://pubs.opengroup.org/onlinepubs/9699919799/)
- Hyprland docs: https://wiki.hyprland.org
- Waybar docs: https://github.com/Alexays/Waybar/wiki

---

**Last Updated**: 2026-02-22  
**Repository**: `/home/groot/projects/scripts`
