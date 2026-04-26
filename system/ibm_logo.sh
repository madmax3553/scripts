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
# Script: ibm_logo.sh
# Purpose: Render the CHIP-8 IBM logo from its original ROM bitmask data
# Dependencies: bash
# Author: groot
# Modified: 2026-04-25

set -euo pipefail

source "/home/groot/projects/scripts/lib/colors.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

BLOCK_COLOR='\033[48;5;26m'
BLOCK="${BLOCK_COLOR}  ${RESET}"
SPACE="  "
COMPACT_BLOCK="${LIGHT_BLUE}█${RESET}"
COMPACT_SPACE=" "
IBM_LOGO_MIN_X=12
IBM_LOGO_MAX_X=56
IBM_LOGO_VISIBLE_MIN_X=12
IBM_LOGO_VISIBLE_MAX_X=51

SPRITE_I_X=12
SPRITE_B_LEFT_X=21
SPRITE_B_RIGHT_X=29
SPRITE_M_LEFT_X=33
SPRITE_M_MIDDLE_X=41
SPRITE_M_RIGHT_X=49

# Each sprite contains the 15 rows for one piece of the original CHIP-8 logo.
SPRITE_I=(0xFF 0x00 0xFF 0x00 0x3C 0x00 0x3C 0x00 0x3C 0x00 0x3C 0x00 0xFF 0x00 0xFF)
SPRITE_B_LEFT=(0xFF 0x00 0xFF 0x00 0x38 0x00 0x3F 0x00 0x3F 0x00 0x38 0x00 0xFF 0x00 0xFF)
SPRITE_B_RIGHT=(0x80 0x00 0xE0 0x00 0xE0 0x00 0x80 0x00 0x80 0x00 0xE0 0x00 0xE0 0x00 0x80)
SPRITE_M_LEFT=(0xF8 0x00 0xFC 0x00 0x3E 0x00 0x3F 0x00 0x3B 0x00 0x39 0x00 0xF8 0x00 0xF8)
SPRITE_M_MIDDLE=(0x03 0x00 0x07 0x00 0x0F 0x00 0xBF 0x00 0xFB 0x00 0xF3 0x00 0xE3 0x00 0x43)
SPRITE_M_RIGHT=(0xE0 0x00 0xE0 0x00 0x80 0x00 0x80 0x00 0x80 0x00 0x80 0x00 0xE0 0x00 0xE0)

# The original IBM Logo CHIP-8 ROM draws these sprites at fixed X coordinates,
# not as a simple concatenated bitmap. Keeping the ROM coordinates preserves the
# 1-pixel I/B gap, joined B halves, and 1-pixel B/M gap.

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────

render_byte() {
    local value="$1"
    local block="$BLOCK"
    local space="$SPACE"

    if [[ "${IBM_LOGO_COMPACT:-0}" == "1" ]]; then
        block="$COMPACT_BLOCK"
        space="$COMPACT_SPACE"
    fi

    for ((bit = 7; bit >= 0; bit--)); do
        if (((value >> bit) & 1)); then
            printf '%b' "$block"
        else
            printf '%s' "$space"
        fi
    done
}

sprite_pixel() {
    local value="$1"
    local sprite_x="$2"
    local x="$3"
    local bit

    if ((x < sprite_x || x > sprite_x + 7)); then
        return 1
    fi

    bit=$((7 - (x - sprite_x)))
    (((value >> bit) & 1))
}

pixel_on() {
    local row="$1"
    local x="$2"
    local on=0

    if sprite_pixel "${SPRITE_I[row]}" "$SPRITE_I_X" "$x"; then
        on=$((on ^ 1))
    fi
    if sprite_pixel "${SPRITE_B_LEFT[row]}" "$SPRITE_B_LEFT_X" "$x"; then
        on=$((on ^ 1))
    fi
    if sprite_pixel "${SPRITE_B_RIGHT[row]}" "$SPRITE_B_RIGHT_X" "$x"; then
        on=$((on ^ 1))
    fi
    if sprite_pixel "${SPRITE_M_LEFT[row]}" "$SPRITE_M_LEFT_X" "$x"; then
        on=$((on ^ 1))
    fi
    if sprite_pixel "${SPRITE_M_MIDDLE[row]}" "$SPRITE_M_MIDDLE_X" "$x"; then
        on=$((on ^ 1))
    fi
    if sprite_pixel "${SPRITE_M_RIGHT[row]}" "$SPRITE_M_RIGHT_X" "$x"; then
        on=$((on ^ 1))
    fi

    ((on == 1))
}

render_logo_row() {
    local row="$1"
    local x
    local block="$BLOCK"
    local space="$SPACE"

    if [[ "${IBM_LOGO_COMPACT:-0}" == "1" ]]; then
        block="$COMPACT_BLOCK"
        space="$COMPACT_SPACE"
    fi

    for ((x = IBM_LOGO_VISIBLE_MIN_X; x <= IBM_LOGO_VISIBLE_MAX_X; x++)); do
        if pixel_on "$row" "$x"; then
            printf '%b' "$block"
        else
            printf '%s' "$space"
        fi
    done
}

logo_indent() {
    local count="${IBM_LOGO_INDENT:-0}"
    local i

    for ((i = 0; i < count; i++)); do
        printf ' '
    done
}

logo_text_indent() {
    local count="${IBM_LOGO_TEXT_INDENT:-${IBM_LOGO_INDENT:-0}}"
    local i

    for ((i = 0; i < count; i++)); do
        printf ' '
    done
}

logo_source_indent() {
    local count="${IBM_LOGO_SOURCE_INDENT:-${IBM_LOGO_INDENT:-0}}"
    local i

    for ((i = 0; i < count; i++)); do
        printf ' '
    done
}

render_logo() {
    local row

    if [[ "${IBM_LOGO_CAPTIONS:-1}" == "1" ]]; then
        printf '\n'
        logo_text_indent
        printf '%bIBM 8-Bar Logo%b (Official CHIP-8 Bitmask Data)\n\n' "$BOLD" "$RESET"
    fi

    for row in {0..14}; do
        logo_indent
        render_logo_row "$row"
        printf '\n'
    done

    if [[ "${IBM_LOGO_CAPTIONS:-1}" == "1" ]]; then
        printf '\n'
        logo_source_indent
        printf '%bBitmask Source:%b IBM Logo.ch8 (1970s ROM)\n\n' "$DIM" "$RESET"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    render_logo
fi
