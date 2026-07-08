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
# Script: passmenu.sh
# Purpose: fuzzel front end for pass(1) — pick an entry, then copy the
#          password, an OTP code, or any field; clipboard auto-clears
# Dependencies: pass, fuzzel, wl-copy, wl-paste, pgrep, find
#               optional: notify-send (keybind feedback), pass-otp (OTP action)
# Author: groot
# Modified: 2026-07-08

set -euo pipefail

source "/home/groot/projects/scripts/lib/colors.sh"
source "/home/groot/projects/scripts/lib/common.sh"

# ─── Keybind-Visible Feedback ────────────────────────────────────────────────
#
# Invoked from a Hyprland keybind: stdout/stderr go nowhere, so every outcome
# must also raise a desktop notification (same convention as iced.sh).

# _notify <urgency> <title> <body>
_notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send --app-name=passmenu --urgency="$1" "$2" "$3" 2>/dev/null || true
}

# Shadow common.sh's die so every fatal path notifies before exiting; must be
# defined *after* sourcing common.sh so this definition wins.
die() {
    local msg="${1:-Unknown error}"
    local code="${2:-1}"
    _notify critical "passmenu: failed" "$msg"
    print_error "$msg"
    exit "$code"
}

# ─── Static Configuration ────────────────────────────────────────────────────

# pass(1) honours PASSWORD_STORE_DIR natively; mirror its default here for the
# entry listing (we never bypass pass for decryption)
readonly STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

# Seconds before the clipboard is wiped (only if it still holds our secret)
readonly CLIP_TIME="${PASSMENU_CLIP_TIME:-45}"

# Action-menu rows.  Fixed prefixes double as dispatch keys; the field rows
# are generated dynamically from the decrypted entry.
readonly ROW_PASS="🔑 copy password"
readonly ROW_OTP="🔢 copy OTP code"
readonly ROW_SHOW="📄 show fields"
readonly ROW_FIELD_PREFIX="📋 copy "

# ─── Security Notes ──────────────────────────────────────────────────────────
#
#   - Secrets travel via pipes/variables only — NEVER as command arguments
#     (argv is world-readable in /proc/<pid>/cmdline)
#   - Log lines carry entry names and action labels, never values
#   - "show fields" redacts the password line and any otpauth:// URI (the
#     TOTP seed is as sensitive as the password itself)
#   - The auto-clear job wipes the clipboard only when it still holds the
#     copied secret, so it can never destroy something copied afterwards

# ─── Helpers ─────────────────────────────────────────────────────────────────

# fuzzel refuses to start when another instance is already up (e.g. the app
# launcher) and exits instantly — which looks exactly like a dead keybind.
_require_fuzzel_free() {
    if pgrep -x fuzzel >/dev/null 2>&1; then
        die "fuzzel is already running; close it and retry" 1
    fi
}

# All store entries as pass-relative names (category/site), sorted
_list_entries() {
    find -L "$STORE_DIR" -name '*.gpg' -type f -printf '%P\n' 2>/dev/null \
        | sed 's/\.gpg$//' \
        | sort
}

# Copy a secret to the Wayland clipboard and schedule the auto-clear.
# _clip_secret <label> <secret>
_clip_secret() {
    local label="$1" secret="$2"

    # wl-copy forks a daemon to serve the selection; >/dev/null keeps it from
    # holding our stdout open (hangs callers that capture output)
    printf '%s' "$secret" | wl-copy >/dev/null 2>&1 \
        || die "wl-copy failed; is the Wayland session alive?" 1

    # Detached clear job.  Comparing first means a later unrelated copy
    # survives; only OUR secret is ever wiped.
    (
        sleep "$CLIP_TIME"
        if [[ "$(wl-paste --no-newline 2>/dev/null)" == "$secret" ]]; then
            wl-copy --clear 2>/dev/null
            _notify low "🔐 passmenu" "Clipboard cleared (${label})"
        fi
    ) >/dev/null 2>&1 & disown

    log_info "Copied ${label}; clear scheduled in ${CLIP_TIME}s"
    print_success "${label} copied (clears in ${CLIP_TIME}s)"
    _notify normal "🔐 passmenu" "${label} copied — clears in ${CLIP_TIME}s"
}

# ─── Main Flow ───────────────────────────────────────────────────────────────

cmd_menu() {
    require_commands "pass" "fuzzel" "wl-copy" "wl-paste" "pgrep"
    [[ -d "$STORE_DIR" ]] || die "Password store not found: ${STORE_DIR}" 1
    _require_fuzzel_free

    # ── Stage 1: pick an entry ──────────────────────────────────────────────
    local entries entry
    entries=$(_list_entries)
    [[ -n "$entries" ]] || die "Password store is empty: ${STORE_DIR}" 1

    entry=$(fuzzel --dmenu \
        --prompt="🔐 pass › " \
        --placeholder="fuzzy-search $(wc -l <<< "$entries") entries…" \
        <<< "$entries") || true
    [[ -n "$entry" ]] || { log_info "passmenu aborted: no entry selected"; exit 0; }

    # Guard against fuzzel returning free-typed text that matches no entry
    grep -qxF "$entry" <<< "$entries" \
        || die "No such entry: ${entry}" 1

    # ── Decrypt once; parse password / fields / otp ─────────────────────────
    # pinentry (pinentry-qt) pops its own dialog when the key is locked
    local content
    content=$(pass show "$entry" 2>/dev/null) \
        || die "Decryption failed for '${entry}' (GPG key locked or missing?)" 1
    log_info "Decrypted entry: ${entry}"

    local password="${content%%$'\n'*}"
    local rest=""
    [[ "$content" == *$'\n'* ]] && rest="${content#*$'\n'}"

    # Fields: `key: value` lines after the password (pass convention).
    # otpauth:// URIs flag OTP support and are never shown or copied raw.
    local -a field_keys=() field_vals=()
    local -A seen_keys=()
    local has_otp=0 line key val
    while IFS= read -r line; do
        if [[ "$line" == otpauth://* ]]; then
            has_otp=1
            continue
        fi
        if [[ "$line" =~ ^([A-Za-z0-9_@.-]+):[[:space:]]*(.+)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            [[ -n "${seen_keys[$key]:-}" ]] && continue
            seen_keys["$key"]=1
            field_keys+=("$key")
            field_vals+=("$val")
        fi
    done <<< "$rest"

    # ── Stage 2: pick an action ─────────────────────────────────────────────
    # Simple entries (just a password) skip the second menu entirely
    if (( has_otp == 0 && ${#field_keys[@]} == 0 )); then
        _clip_secret "Password [${entry}]" "$password"
        return 0
    fi

    local -a rows=("$ROW_PASS")
    (( has_otp )) && rows+=("$ROW_OTP")
    local k
    for k in "${field_keys[@]}"; do
        rows+=("${ROW_FIELD_PREFIX}${k}")
    done
    rows+=("$ROW_SHOW")

    local action
    action=$(printf '%s\n' "${rows[@]}" | fuzzel --dmenu \
        --prompt="⚡ ${entry} › " \
        --placeholder="choose what to copy…") || true
    [[ -n "$action" ]] || { log_info "passmenu aborted: no action selected"; exit 0; }

    # ── Dispatch ────────────────────────────────────────────────────────────
    case "$action" in
        "$ROW_PASS")
            _clip_secret "Password [${entry}]" "$password"
            ;;
        "$ROW_OTP")
            local otp
            otp=$(pass otp "$entry" 2>/dev/null) \
                || die "OTP generation failed (is pass-otp installed?)" 1
            _clip_secret "OTP [${entry}]" "$otp"
            ;;
        "$ROW_SHOW")
            # Password and otpauth already excluded from field parsing —
            # only the survivable metadata is displayed
            local shown="" i
            for i in "${!field_keys[@]}"; do
                shown+="${field_keys[$i]}: ${field_vals[$i]}"$'\n'
            done
            _notify normal "🔐 ${entry}" "${shown%$'\n'}"
            printf '%s' "$shown"
            log_info "Showed fields for ${entry}"
            ;;
        "$ROW_FIELD_PREFIX"*)
            local want="${action#"$ROW_FIELD_PREFIX"}" found=0 i
            for i in "${!field_keys[@]}"; do
                if [[ "${field_keys[$i]}" == "$want" ]]; then
                    _clip_secret "${want} [${entry}]" "${field_vals[$i]}"
                    found=1
                    break
                fi
            done
            (( found )) || die "Field vanished from entry: ${want}" 1
            ;;
        *)
            die "Unknown action: ${action}" 1
            ;;
    esac
}

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    printf '%b\n' "$(cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [menu]

fuzzel-driven front end for pass(1), clipboard-only.

${BOLD}Flow:${RESET}
  1. fuzzy-pick an entry from the store
  2. pick an action — dynamic per entry:
       ${ROW_PASS}      always
       ${ROW_OTP}      when the entry carries an otpauth:// URI
       ${ROW_FIELD_PREFIX}<key>       one row per 'key: value' field (user, url, …)
       ${ROW_SHOW}       notification with the non-secret fields
     (entries with only a password skip straight to the copy)

${BOLD}Clipboard:${RESET} auto-clears after ${CLIP_TIME}s — only if it still holds the
copied secret.  Override with PASSMENU_CLIP_TIME.

${BOLD}Store:${RESET} ${STORE_DIR}  (PASSWORD_STORE_DIR honoured)

${BOLD}Hyprland keybind (configs/keybinds.lua):${RESET}
  hl.bind(mod_shift("P"), hl.dsp.exec_cmd("~/.local/bin/launcher/passmenu.sh"))
EOF
)"
}

# ─── Entrypoint ──────────────────────────────────────────────────────────────

case "${1:-menu}" in
    menu)           cmd_menu ;;
    -h|--help|help) usage; exit 0 ;;
    *)              usage >&2; exit 1 ;;
esac
