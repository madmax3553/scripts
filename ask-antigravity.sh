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
# Script: ask-antigravity.sh
# Purpose: Start a duplex Antigravity chat from a quick desktop prompt
# Dependencies: agy, fuzzel optional, notify-send optional, terminal optional
# Author: groot
# Modified: 2026-06-05

set -euo pipefail

APP_NAME="Ask Antigravity"
CLI_NAME="agy"
MODE="interactive"
CONTINUE_SESSION=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [question]

Start an interactive Antigravity CLI session. When no question is supplied,
prompt with fuzzel/wofi/rofi or stdin first.

Options:
  -p, --print       One-shot mode: print one answer and show it in the menu
  -c, --continue    Continue the most recent AGY conversation
  -h, --help        Show this help

Environment:
  AGY_MODEL                    Optional Antigravity model override
  ANTIGRAVITY_MODEL            Optional Antigravity model override
  ASK_ANTIGRAVITY_WORKDIR      Working directory for AGY, defaults to HOME
  ASK_ANTIGRAVITY_INSTRUCTION  Prompt prefix for quick-answer style
  ASK_ANTIGRAVITY_WRAP         Answer wrap width, defaults to 96
  ASK_ANTIGRAVITY_PROGRESS     Set to 0 to disable print-mode notifications
  ASK_ANTIGRAVITY_TIMEOUT      Print-mode timeout, defaults to 2m
  ASK_ANTIGRAVITY_TERMINAL     Terminal for launcher mode, defaults to TERMINAL
EOF
}

progress_id=""
progress_pid=""
AGY_ARGS=()

short_text() {
    local text="$1"
    local limit="${2:-80}"

    text=${text//$'\n'/ }
    if ((${#text} > limit)); then
        printf '%s...' "${text:0:limit}"
    else
        printf '%s' "$text"
    fi
}

notify_error() {
    local message="$1"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="$APP_NAME" "$APP_NAME" "$message" >/dev/null 2>&1 || true
    else
        printf 'ask-antigravity: %s\n' "$message" >&2
    fi
}

start_progress() {
    local question="$1"
    local short_question
    local progress="${ASK_ANTIGRAVITY_PROGRESS:-1}"

    [[ "$progress" != "0" ]] || return 0
    command -v notify-send >/dev/null 2>&1 || return 0

    short_question=$(short_text "$question" 72)
    progress_id=$(
        notify-send \
            --print-id \
            --expire-time=0 \
            --app-name="$APP_NAME" \
            "$APP_NAME" \
            "Thinking... ${short_question}" 2>/dev/null || true
    )

    [[ "$progress_id" =~ ^[0-9]+$ ]] || {
        progress_id=""
        return 0
    }

    (
        frames=("Thinking" "Thinking." "Thinking.." "Thinking...")
        index=0

        while :; do
            sleep 1
            notify-send \
                --replace-id="$progress_id" \
                --expire-time=0 \
                --app-name="$APP_NAME" \
                "$APP_NAME" \
                "${frames[index % ${#frames[@]}]} ${short_question}" >/dev/null 2>&1 ||
                    exit 0
            index=$((index + 1))
        done
    ) &
    progress_pid=$!
}

stop_progress() {
    local message="${1:-Answer ready.}"
    local expire_ms="${2:-1800}"

    if [[ -n "$progress_pid" ]]; then
        kill "$progress_pid" >/dev/null 2>&1 || true
        wait "$progress_pid" 2>/dev/null || true
        progress_pid=""
    fi

    if [[ "$progress_id" =~ ^[0-9]+$ ]] && command -v notify-send >/dev/null 2>&1; then
        notify-send \
            --replace-id="$progress_id" \
            --expire-time="$expire_ms" \
            --app-name="$APP_NAME" \
            "$APP_NAME" \
            "$message" >/dev/null 2>&1 || true
    fi

    progress_id=""
}

cleanup() {
    stop_progress "Cancelled." 1200
}

prompt_question() {
    local question

    if command -v fuzzel >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        if question=$(fuzzel --dmenu \
            --prompt-only="${APP_NAME}: " \
            --placeholder="quick question" \
            --width 80 \
            --border-radius 12 \
            --border-width 2 2>/dev/null); then
            printf '%s\n' "$question"
            return 0
        fi
    elif command -v wofi >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        if question=$(wofi --dmenu --prompt "$APP_NAME" 2>/dev/null); then
            printf '%s\n' "$question"
            return 0
        fi
    elif command -v rofi >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        if question=$(rofi -dmenu -p "$APP_NAME" 2>/dev/null); then
            printf '%s\n' "$question"
            return 0
        fi
    fi

    printf '%s: ' "$APP_NAME" >&2
    IFS= read -r question || return 1
    printf '%s\n' "$question"
}

prompt_text() {
    local question="$1"
    local instruction="${ASK_ANTIGRAVITY_INSTRUCTION:-}"

    if [[ -n "$instruction" ]]; then
        printf '%s\n\nQuestion: %s' "$instruction" "$question"
    else
        printf '%s' "$question"
    fi
}

common_agy_args() {
    local model="${AGY_MODEL:-${ANTIGRAVITY_MODEL:-}}"

    if [[ -n "$model" ]]; then
        printf '%s\0' --model "$model"
    fi

    if ((CONTINUE_SESSION == 1)); then
        printf '%s\0' --continue
    fi
}

interactive_agy_args() {
    local question="$1"

    common_agy_args

    if [[ -n "$question" ]]; then
        printf '%s\0' --prompt-interactive "$(prompt_text "$question")"
    fi
}

print_agy_args() {
    local question="$1"
    local timeout="${ASK_ANTIGRAVITY_TIMEOUT:-2m}"
    local default_instruction instruction

    default_instruction="Answer this quick desktop question directly and concisely."
    default_instruction+=" Do not use tools, read files, or modify files."
    instruction="${ASK_ANTIGRAVITY_INSTRUCTION:-$default_instruction}"

    common_agy_args
    printf '%s\0' \
        --print-timeout "$timeout" \
        --print "$(printf '%s\n\nQuestion: %s' "$instruction" "$question")"
}

collect_agy_args() {
    local generator="$1"
    local question="$2"
    local arg

    AGY_ARGS=()
    while IFS= read -r -d '' arg; do
        AGY_ARGS+=("$arg")
    done < <("$generator" "$question")
}

select_terminal() {
    local configured="${ASK_ANTIGRAVITY_TERMINAL:-${TERMINAL:-}}"
    local candidate

    if [[ -n "$configured" ]] && command -v "$configured" >/dev/null 2>&1; then
        printf '%s' "$configured"
        return 0
    fi

    for candidate in ghostty kitty alacritty foot wezterm xterm; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

spawn_terminal() {
    local terminal="$1"
    shift

    local -a cmd=()
    case "$(basename "$terminal")" in
        ghostty)
            cmd=("$terminal" --title="$APP_NAME" -e "$@")
            ;;
        kitty)
            cmd=("$terminal" --title "$APP_NAME" "$@")
            ;;
        alacritty)
            cmd=("$terminal" --title "$APP_NAME" -e "$@")
            ;;
        foot)
            cmd=("$terminal" --title="$APP_NAME" "$@")
            ;;
        wezterm)
            cmd=("$terminal" start -- "$@")
            ;;
        xterm)
            cmd=("$terminal" -T "$APP_NAME" -e "$@")
            ;;
        *)
            cmd=("$terminal" -e "$@")
            ;;
    esac

    setsid "${cmd[@]}" >/dev/null 2>&1 &
}

run_interactive() {
    local question="$1"
    local workdir="${ASK_ANTIGRAVITY_WORKDIR:-$HOME}"
    local terminal=""
    local -a shell_cmd=()

    if ! command -v "$CLI_NAME" >/dev/null 2>&1; then
        notify_error "Antigravity CLI ($CLI_NAME) is not installed."
        return 127
    fi

    collect_agy_args interactive_agy_args "$question"

    if [[ -t 0 && -t 1 ]]; then
        cd "$workdir"
        exec "$CLI_NAME" "${AGY_ARGS[@]}"
    fi

    if ! terminal="$(select_terminal)"; then
        notify_error "No terminal found for interactive AGY session."
        return 127
    fi

    shell_cmd=(
        bash
        -lc
        'cd "$1" || exit; shift; exec "$@"'
        bash
        "$workdir"
        "$CLI_NAME"
        "${AGY_ARGS[@]}"
    )
    spawn_terminal "$terminal" "${shell_cmd[@]}"
}

run_print() {
    local question="$1"
    local workdir="${ASK_ANTIGRAVITY_WORKDIR:-$HOME}"

    if ! command -v "$CLI_NAME" >/dev/null 2>&1; then
        printf 'Antigravity CLI (%s) is not installed.\n' "$CLI_NAME" >&2
        return 127
    fi

    cd "$workdir"
    collect_agy_args print_agy_args "$question"
    "$CLI_NAME" "${AGY_ARGS[@]}"
}

format_answer() {
    local wrap_width="${ASK_ANTIGRAVITY_WRAP:-96}"

    fold -s -w "$wrap_width" | sed 's/^$/ /'
}

display_lines() {
    local title="$1"
    local message="$2"

    if command -v fuzzel >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        if fuzzel --dmenu \
            --prompt="Antigravity: " \
            --mesg="$title" \
            --mesg-mode=wrap \
            --width 100 \
            --lines 24 \
            --no-sort \
            --only-match \
            --border-radius 12 \
            --border-width 2 >/dev/null 2>&1; then
            return 0
        fi
    elif command -v wofi >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        if wofi --dmenu --prompt "$message" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v rofi >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        if rofi -dmenu -p "$message" >/dev/null 2>&1; then
            return 0
        fi
    fi

    cat
}

display_answer() {
    local question="$1"
    local answer="$2"

    printf '%s\n' "$answer" |
        format_answer |
        display_lines "Question: $question" "Antigravity"
}

args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--print)
            MODE="print"
            shift
            ;;
        -c|--continue)
            CONTINUE_SESSION=1
            shift
            ;;
        --)
            shift
            args+=("$@")
            break
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

question="${args[*]:-}"
if [[ -z "$question" && "$MODE" == "print" ]]; then
    question=$(prompt_question || true)
elif [[ -z "$question" && "$CONTINUE_SESSION" -eq 0 ]]; then
    question=$(prompt_question || true)
fi

if [[ -z "$question" && "$CONTINUE_SESSION" -eq 0 ]]; then
    exit 0
fi

if [[ "$MODE" == "print" ]]; then
    [[ -n "$question" ]] || exit 0

    trap cleanup EXIT
    start_progress "$question"

    if ! answer=$(run_print "$question" 2>&1); then
        stop_progress "Antigravity failed." 3000
        trap - EXIT
        display_answer "$question" "$answer"
        exit 1
    fi

    stop_progress "Answer ready." 1200
    trap - EXIT

    if [[ -z "${answer//[[:space:]]/}" ]]; then
        answer="Antigravity returned no output."
    fi

    display_answer "$question" "$answer"
    exit 0
fi

run_interactive "$question"
