# User Scripts Repository

Single source of truth for all custom shell scripts and utilities.

## Structure

Scripts are organized by purpose into the following categories:

| Category | Purpose | Scripts |
|----------|---------|---------|
| **waybar** | Waybar status bar modules | charge-waybar, cliphist-waybar, waybar-repostatus, yay-waybar |
| **hypr** | Hyprland window manager utilities | monitor, monitor_setup, scratchpad, toggle, window-switcher, wallpaper |
| **system** | System and desktop utilities | charge-rate, notifications, remote, update-mirrors, wallpaper, wlogout-custom, dotfiles-status |
| **journal** | Note-taking and todo management | journal, start-journal, wiki-daily-plan, wiki-helper, wiki-review-todos |
| **launcher** | Application launchers | launcher, scope, stfc-launch |
| **clipboard** | Clipboard utilities | cliphist-watch, txtcliphist |
| **other** | Miscellaneous utilities | arch-audit, bin-manager, config, install, startgp, update, wifi, wifistatus |
| **lib** | Shared libraries | colors.sh, common.sh, waybar-cache.sh |

## Usage

Access scripts through `~/.local/bin/` (via GNU Stow):

```bash
# Waybar modules
~/.local/bin/waybar/charge-waybar.sh

# Hyprland utilities
~/.local/bin/hypr/monitor.sh

# System utilities
~/.local/bin/system/wallpaper.sh

# Journal/notes
~/.local/bin/journal/start-journal.sh

# Shared libraries
source ~/.local/bin/lib/colors.sh
```

## Architecture

```
~/.local/bin/script                     (User accesses here)
  ↓ (GNU Stow symlink)
~/dotfiles/bin/.local/bin/script        (Symlink layer)
  ↓ (Relative symlink)
~/projects/scripts/{category}/script    (Source of truth)
```

## Adding New Scripts

1. Place script in appropriate category directory
2. Make executable: `chmod +x script.sh`
3. If script uses libraries, source via absolute path:
   ```bash
   source /home/groot/projects/scripts/lib/colors.sh
   ```
4. Commit to git

## Library Functions

### colors.sh
ANSI color codes for terminal output

### common.sh
Common utility functions

### waybar-cache.sh
Caching utilities for Waybar modules

## Requirements

- Bash 4.0+
- Various system utilities (nmcli, tofi, fzf, etc.) - see individual scripts

## License

Personal use

## Archive

Older versions and deprecated scripts are kept in `archive/old-versions/`
