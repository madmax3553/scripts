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
# Script: groot-splash.sh
# Purpose: Display a standalone IBM-inspired Groot boot splash screen
# Dependencies: bash, cat, date, sleep, stty, tput, uname
# Author: groot
# Modified: 2026-04-25

set -euo pipefail

source "/home/groot/projects/scripts/lib/colors.sh"
source "/home/groot/projects/scripts/lib/common.sh"
source "/home/groot/projects/scripts/system/ibm_logo.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

DEFAULT_MESSAGE="Personal Computing Environment"
DEFAULT_DURATION="2"
DEFAULT_SPEED="0.04"
FRAME_INNER_WIDTH=76
IBM_LOGO_WIDTH=80
IBM_LOGO_COMPACT_WIDTH=40
IBM_LOGO_TITLE_WIDTH=48
IBM_LOGO_SOURCE_WIDTH=43
IBM_LOGO_MIN_MARGIN=4
GROOT_MARK_WIDTH=44
BOOT_BLOCK_WIDTH=74

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Display an IBM-inspired Groot boot splash screen.

Options:
  -m message    Subtitle shown under the Groot mark
  -d seconds    Hold time after rendering (default: ${DEFAULT_DURATION})
  -s seconds    Delay between boot lines (default: ${DEFAULT_SPEED})
  -n            Do not clear the terminal before rendering
  -D            Print layout measurements and exit
  -h            Show this help
EOF
}

repeat_char() {
    local char="$1"
    local count="$2"
    local i

    for ((i = 0; i < count; i++)); do
        printf '%s' "$char"
    done
}

terminal_columns() {
    local rows_cols
    local cols

    if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && ((COLUMNS > 0)); then
        printf '%s' "$COLUMNS"
        return
    fi

    if rows_cols="$(stty size 2>/dev/null || stty size </dev/tty 2>/dev/null)"; then
        rows_cols="${rows_cols##* }"
        if [[ "$rows_cols" =~ ^[0-9]+$ ]] && ((rows_cols > 0)); then
            printf '%s' "$rows_cols"
            return
        fi
    fi

    if cols="$(tput cols 2>/dev/null)"; then
        if [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
            printf '%s' "$cols"
            return
        fi
    fi

    printf '80'
}

center_indent() {
    local width="$1"
    local columns="$2"

    if ((columns > width)); then
        printf '%s' "$(((columns - width) / 2))"
    else
        printf '0'
    fi
}

print_indent() {
    local count="$1"
    local i

    for ((i = 0; i < count; i++)); do
        printf ' '
    done
}

center_text() {
    local text="$1"
    local width="$2"
    local columns="$3"
    local color="${4:-}"
    local indent

    indent="$(center_indent "$width" "$columns")"
    print_indent "$indent"
    printf '%b%s%b\n' "$color" "$text" "$RESET"
}

layout_debug() {
    cat <<EOF
columns=${LAYOUT_COLUMNS}
frame_width=${FRAME_WIDTH} frame_indent=${FRAME_INDENT}
ibm_logo_width=${IBM_LOGO_ACTIVE_WIDTH} ibm_logo_indent=${IBM_LOGO_INDENT} compact=${IBM_LOGO_COMPACT}
ibm_title_width=${IBM_LOGO_TITLE_WIDTH} ibm_title_indent=${IBM_LOGO_TEXT_INDENT}
ibm_source_width=${IBM_LOGO_SOURCE_WIDTH} ibm_source_indent=${IBM_LOGO_SOURCE_INDENT}
groot_mark_width=${GROOT_MARK_WIDTH} groot_mark_indent=${GROOT_MARK_INDENT}
boot_block_width=${BOOT_BLOCK_WIDTH} boot_block_indent=${BOOT_BLOCK_INDENT}
EOF
}

calculate_layout() {
    LAYOUT_COLUMNS="$(terminal_columns)"
    FRAME_WIDTH=$((FRAME_INNER_WIDTH + 2))
    IBM_LOGO_ACTIVE_WIDTH="$IBM_LOGO_WIDTH"

    if ((LAYOUT_COLUMNS < IBM_LOGO_WIDTH + IBM_LOGO_MIN_MARGIN)); then
        IBM_LOGO_COMPACT="1"
        IBM_LOGO_ACTIVE_WIDTH="$IBM_LOGO_COMPACT_WIDTH"
    else
        IBM_LOGO_COMPACT="0"
    fi

    FRAME_INDENT="$(center_indent "$FRAME_WIDTH" "$LAYOUT_COLUMNS")"
    IBM_LOGO_INDENT="$(center_indent "$IBM_LOGO_ACTIVE_WIDTH" "$LAYOUT_COLUMNS")"
    IBM_LOGO_TEXT_INDENT="$(center_indent "$IBM_LOGO_TITLE_WIDTH" "$LAYOUT_COLUMNS")"
    IBM_LOGO_SOURCE_INDENT="$(center_indent "$IBM_LOGO_SOURCE_WIDTH" "$LAYOUT_COLUMNS")"
    GROOT_MARK_INDENT="$(center_indent "$GROOT_MARK_WIDTH" "$LAYOUT_COLUMNS")"
    BOOT_BLOCK_INDENT="$(center_indent "$BOOT_BLOCK_WIDTH" "$LAYOUT_COLUMNS")"
}

frame_line() {
    local text="${1:-}"

    print_indent "${FRAME_INDENT:-0}"
    printf '%b|%b %-74s %b|%b\n' "$BLUE" "$RESET" "$text" "$BLUE" "$RESET"
}

frame_rule() {
    print_indent "${FRAME_INDENT:-0}"
    printf '%b+%s+%b\n' "$BLUE" "$(repeat_char '-' "$FRAME_INNER_WIDTH")" "$RESET"
}

frame_bottom() {
    print_indent "${FRAME_INDENT:-0}"
    printf '%b+%s+%b\n' "$BLUE" "$(repeat_char '-' "$FRAME_INNER_WIDTH")" "$RESET"
}

render_groot_mark() {
    printf '%b' "$LIGHT_BLUE"
    while IFS= read -r line; do
        print_indent "${GROOT_MARK_INDENT:-0}"
        printf '%s\n' "$line"
    done <<'EOF'
  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓
 ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒
▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░
░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░
░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░
 ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░
  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░
░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░
      ░    ░         ░ ░      ░ ░
EOF
    printf '%b' "$RESET"
}

boot_line() {
    local label="$1"
    local value="$2"
    local speed="$3"

    print_indent "${BOOT_BLOCK_INDENT:-0}"
    printf '  %-24s [%b OK %b] %s\n' "$label" "$SUCCESS" "$RESET" "$value"
    sleep "$speed"
}

render_progress() {
    local duration="$1"
    local width=34
    local step
    local indent

    indent="$(repeat_char ' ' "${BOOT_BLOCK_INDENT:-0}")"

    printf '\n%s  Initializing ' "$indent"
    for ((step = 0; step <= width; step++)); do
        printf '\r%s  Initializing [%b%s%b%s] %3d%%' "$indent" \
            "$BLUE" "$(repeat_char '#' "$step")" "$RESET" \
            "$(repeat_char '.' "$((width - step))")" "$((step * 100 / width))"
        sleep 0.02
    done
    printf '\n'

    sleep "$duration"
}

render_splash() {
    local message="$1"
    local duration="$2"
    local speed="$3"
    local clear_screen="$4"
    local host
    local kernel
    local now

    host="$(uname -n 2>/dev/null || printf 'localhost')"
    if [[ -r /proc/sys/kernel/hostname ]]; then
        host="$(< /proc/sys/kernel/hostname)"
    fi
    kernel="$(uname -sr 2>/dev/null || printf 'Linux')"
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    calculate_layout

    if [[ "$clear_screen" == "1" ]]; then
        printf '\033[2J\033[H'
    fi

    frame_rule
    frame_line "IBM Personal Computer compatible boot sequence"
    frame_line "Copyright (C) 1981-2026 Groot Systems"
    frame_bottom

    # Standalone ibm_logo.sh keeps captions for provenance; splash hides them
    # for a cleaner boot-screen layout.
    IBM_LOGO_CAPTIONS="0"
    printf '\n\n'
    render_logo
    printf '\n\n'
    render_groot_mark

    printf '\n'
    center_text "GROOT" 5 "$LAYOUT_COLUMNS" "$BOLD"
    center_text "$message" "${#message}" "$LAYOUT_COLUMNS" "$DIM"
    printf '\n'

    boot_line "System board" "${host}" "$speed"
    boot_line "Kernel" "${kernel}" "$speed"
    boot_line "Firmware date" "${now}" "$speed"
    boot_line "Display adapter" "ANSI terminal mode" "$speed"
    boot_line "Session target" "ready" "$speed"

    render_progress "$duration"
    printf '\n'
    center_text "Press Ctrl+C for setup. Booting Groot environment..." 53 "$LAYOUT_COLUMNS" "$DIM"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

message="$DEFAULT_MESSAGE"
duration="$DEFAULT_DURATION"
speed="$DEFAULT_SPEED"
clear_screen="1"
debug_layout="0"

require_commands "cat" "date" "sleep" "uname"

while getopts ":m:d:s:nDh" opt; do
    case "$opt" in
        m) message="$OPTARG" ;;
        d) duration="$OPTARG" ;;
        s) speed="$OPTARG" ;;
        n) clear_screen="0" ;;
        D) debug_layout="1" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

if [[ "$debug_layout" == "1" ]]; then
    calculate_layout
    layout_debug
    exit 0
fi

render_splash "$message" "$duration" "$speed" "$clear_screen"
