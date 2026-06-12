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
# Script: netstatus.sh
# Purpose: Display local network interface status in a Groot-styled terminal panel
# Dependencies: ip, awk, date; optional: nmcli, resolvectl, tput
# Author: groot
# Modified: 2026-06-11

set -euo pipefail

source "/home/groot/projects/scripts/lib/colors.sh"
SCRIPT_NAME="netstatus.sh"
source "/home/groot/projects/scripts/lib/common.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

NA="N/A"
DEFAULT_BOX_WIDTH=72
MIN_BOX_WIDTH=52
LABEL_WIDTH=15

NO_COLOR_MODE=0
PAUSE_ON_EXIT=0
OPEN_TERMINAL=0
DEBUG_MODE=0
DIAGNOSE_MODE=0
BOX_WIDTH="$DEFAULT_BOX_WIDTH"
VALUE_WIDTH=0

BORDER_COLOR="$BLUE"
TITLE_COLOR="$LIGHT_CYAN"
SECTION_COLOR="$SECTION"
LABEL_COLOR="$YELLOW"
VALUE_COLOR="$LIGHT_WHITE"
MUTED_COLOR="$DIM"
STATUS_UP_COLOR="$SUCCESS"
STATUS_DOWN_COLOR="$ERROR"
RESET_COLOR="$RESET"

INTERFACE="$NA"
STATUS="DOWN"
TYPE="$NA"
CONNECTION="$NA"
MAC="$NA"
IP_ADDR="$NA"
NETMASK="$NA"
GATEWAY="$NA"
DNS="$NA"
DHCP_SERVER="$NA"
LEASE_TIME="$NA"
LEASE_EXPIRY="$NA"

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Display the active network interface, address, gateway, DNS, and DHCP lease.

Options:
  -p, --pause     Wait for Enter before exiting
  -t, --terminal  Open in a terminal when launched without a TTY
  -n, --no-color  Disable ANSI color output
  -d, --debug     Print launch diagnostics to stderr
  -D, --diagnose  Print launch and network diagnostics
  -h, --help      Show this help

Environment:
  NETSTATUS_WIDTH  Override panel width (default: ${DEFAULT_BOX_WIDTH})
  TERMINAL         Preferred terminal when launched without a TTY
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            -p|--pause)
                PAUSE_ON_EXIT=1
                shift
                ;;
            -t|--terminal)
                OPEN_TERMINAL=1
                shift
                ;;
            -n|--no-color)
                NO_COLOR_MODE=1
                shift
                ;;
            -d|--debug)
                DEBUG_MODE=1
                shift
                ;;
            -D|--diagnose)
                DEBUG_MODE=1
                DIAGNOSE_MODE=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                exit 1
                ;;
        esac
    done
}

debug_line() {
    ((DEBUG_MODE)) || return 0
    printf 'netstatus debug: %s\n' "$*" >&2
}

trace_line() {
    [[ -d "$LOG_DIR" && -w "$LOG_DIR" ]] || return 0
    [[ ! -e "$LOG_FILE" || -w "$LOG_FILE" ]] || return 0
    printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" || true
}

tty_state() {
    local fd="$1"

    if [[ -t "$fd" ]]; then
        printf 'yes'
    else
        printf 'no'
    fi
}

fd_target() {
    local fd="$1"
    local target

    target="$(readlink "/proc/$$/fd/${fd}" 2>/dev/null || true)"
    [[ -n "$target" ]] && printf '%s' "$target" || printf 'unknown'
}

parent_command() {
    local ppid="${PPID:-}"

    [[ -n "$ppid" ]] || return 0
    ps -p "$ppid" -o comm= 2>/dev/null | awk 'NF {print; exit}' || true
}

tty_open_state() {
    local tty_fd

    if { exec {tty_fd}>/dev/tty; } 2>/dev/null; then
        exec {tty_fd}>&-
        printf 'yes'
    else
        printf 'no'
    fi
}

log_invocation() {
    trace_line "start script=$(script_path) args=$*"
    trace_line "cwd=$PWD parent=$(parent_command) pid=$$ ppid=${PPID:-unknown}"
    trace_line "tty stdin=$(tty_state 0):$(fd_target 0) stdout=$(tty_state 1):$(fd_target 1) stderr=$(tty_state 2):$(fd_target 2)"
    trace_line "PATH=$PATH"
}

script_path() {
    local source_path="${BASH_SOURCE[0]}"
    local resolved

    if command -v readlink >/dev/null 2>&1; then
        resolved="$(readlink -f -- "$source_path" 2>/dev/null || true)"
        if [[ -n "$resolved" ]]; then
            printf '%s' "$resolved"
            return
        fi
    fi

    printf '%s' "$source_path"
}

diagnose() {
    local cmd

    cat <<EOF
netstatus diagnostics
script:      $(script_path)
cwd:         $PWD
parent:      $(parent_command)
pid/ppid:    $$/${PPID:-unknown}
stdin:       tty=$(tty_state 0) target=$(fd_target 0)
stdout:      tty=$(tty_state 1) target=$(fd_target 1)
stderr:      tty=$(tty_state 2) target=$(fd_target 2)
/dev/tty:    readable=$([[ -r /dev/tty ]] && printf yes || printf no) writable=$([[ -w /dev/tty ]] && printf yes || printf no)
/dev/tty fd: writable=$(tty_open_state)
PATH:        $PATH

commands:
EOF

    for cmd in ip awk date nmcli resolvectl tput ghostty kitty notify-send; do
        printf '  %-12s %s\n' "$cmd" "$(command -v "$cmd" 2>/dev/null || printf 'missing')"
    done

    cat <<EOF

network probes:
$(ip route show default 2>&1 | sed 's/^/  ip route default: /')
$(ip -o link show up 2>&1 | sed 's/^/  ip link up:       /')

log file:
  $LOG_FILE
EOF
}

terminal_candidates() {
    local seen=""
    local candidate

    if [[ -n "${TERMINAL:-}" ]]; then
        printf '%s\n' "$TERMINAL"
        seen=":${TERMINAL}:"
    fi

    for candidate in ghostty kitty alacritty foot wezterm konsole gnome-terminal xterm; do
        [[ "$seen" == *":${candidate}:"* ]] && continue
        printf '%s\n' "$candidate"
    done
}

launch_terminal() {
    local terminal="$1"
    local command="$2"
    local terminal_name

    terminal_name="$(basename "$terminal")"

    case "$terminal_name" in
        wezterm)
            "$terminal" start -- bash -lc "$command"
            ;;
        gnome-terminal|kgx)
            "$terminal" -- bash -lc "$command"
            ;;
        *)
            "$terminal" -e bash -lc "$command"
            ;;
    esac
}

maybe_reopen_in_terminal() {
    local source_path
    local quoted_source
    local command
    local terminal

    ((OPEN_TERMINAL)) || return 0
    [[ "${NETSTATUS_NO_REEXEC:-0}" == "1" ]] && return 0
    [[ -t 0 || -t 1 ]] && return 0

    source_path="$(script_path)"
    printf -v quoted_source '%q' "$source_path"
    command="NETSTATUS_NO_REEXEC=1 ${quoted_source} --pause"
    debug_line "detached launch detected; trying terminal reexec"

    while IFS= read -r terminal; do
        command -v "$terminal" >/dev/null 2>&1 || continue
        debug_line "trying terminal: $terminal"
        if launch_terminal "$terminal" "$command" >/dev/null 2>&1; then
            debug_line "terminal launch succeeded: $terminal"
            exit 0
        fi
        debug_line "terminal launch failed: $terminal"
    done < <(terminal_candidates)

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Network Status" "Open a terminal and run: netstatus.sh" || true
    fi
}

route_visible_output() {
    local tty_fd

    if [[ -t 1 ]]; then
        return 0
    fi

    if [[ -t 0 || -t 2 ]]; then
        if { exec {tty_fd}>/dev/tty; } 2>/dev/null; then
            exec 1>&"$tty_fd"
            debug_line "stdout is not a TTY; rendering to /dev/tty"
            trace_line "routed output to /dev/tty"
            return 0
        fi
    fi

    if [[ -t 2 ]]; then
        exec 1>&2
        debug_line "stdout is not a TTY; rendering to stderr"
        trace_line "routed output to stderr"
    fi
}

disable_colors_if_needed() {
    if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
        NO_COLOR_MODE=1
    fi

    if ((NO_COLOR_MODE)); then
        BORDER_COLOR=""
        TITLE_COLOR=""
        SECTION_COLOR=""
        LABEL_COLOR=""
        VALUE_COLOR=""
        MUTED_COLOR=""
        STATUS_UP_COLOR=""
        STATUS_DOWN_COLOR=""
        RESET_COLOR=""
    fi
}

terminal_columns() {
    local cols

    if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && ((COLUMNS > 0)); then
        printf '%s' "$COLUMNS"
        return
    fi

    if command -v tput >/dev/null 2>&1; then
        if cols="$(tput cols 2>/dev/null)" && [[ "$cols" =~ ^[0-9]+$ ]] && ((cols > 0)); then
            printf '%s' "$cols"
            return
        fi
    fi

    printf '80'
}

calculate_layout() {
    local cols
    local requested="${NETSTATUS_WIDTH:-$DEFAULT_BOX_WIDTH}"

    if [[ "$requested" =~ ^[0-9]+$ ]] && ((requested >= MIN_BOX_WIDTH)); then
        BOX_WIDTH="$requested"
    else
        BOX_WIDTH="$DEFAULT_BOX_WIDTH"
    fi

    cols="$(terminal_columns)"
    if ((cols > 0 && cols < BOX_WIDTH)); then
        BOX_WIDTH="$cols"
    fi

    if ((BOX_WIDTH < MIN_BOX_WIDTH)); then
        BOX_WIDTH="$MIN_BOX_WIDTH"
    fi

    VALUE_WIDTH=$((BOX_WIDTH - LABEL_WIDTH - 8))
}

repeat_char() {
    local char="$1"
    local count="$2"
    local i

    for ((i = 0; i < count; i++)); do
        printf '%s' "$char"
    done
}

trim() {
    local value="$*"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

normalize_list() {
    local raw="$1"
    local strip_cidr="${2:-0}"
    local item
    local value
    local result=""
    local -a items

    raw="${raw//$'\r'/}"
    raw="${raw//$'\n'/|}"
    raw="${raw// | /|}"

    IFS='|' read -r -a items <<< "$raw"
    for item in "${items[@]}"; do
        value="$(trim "$item")"
        [[ -z "$value" ]] && continue

        if [[ "$strip_cidr" == "1" && "$value" == */* ]]; then
            value="${value%%/*}"
        fi

        if [[ -z "$result" ]]; then
            result="$value"
        else
            result="${result}, ${value}"
        fi
    done

    printf '%s' "$result"
}

first_list_item() {
    local raw="$1"
    local item
    local value
    local -a items

    raw="${raw//$'\r'/}"
    raw="${raw//$'\n'/|}"
    raw="${raw// | /|}"

    IFS='|' read -r -a items <<< "$raw"
    for item in "${items[@]}"; do
        value="$(trim "$item")"
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return
        fi
    done
}

cidr_to_netmask() {
    local cidr="$1"
    local full_octets
    local remainder
    local octet
    local i
    local output=""

    if [[ ! "$cidr" =~ ^[0-9]+$ ]] || ((cidr < 0 || cidr > 32)); then
        printf '%s' "$NA"
        return
    fi

    full_octets=$((cidr / 8))
    remainder=$((cidr % 8))

    for ((i = 0; i < 4; i++)); do
        if ((i < full_octets)); then
            octet=255
        elif ((i == full_octets && remainder > 0)); then
            octet=$((256 - (1 << (8 - remainder))))
        else
            octet=0
        fi

        if [[ -z "$output" ]]; then
            output="$octet"
        else
            output="${output}.${octet}"
        fi
    done

    printf '%s' "$output"
}

extract_dhcp_option() {
    local option_name="$1"
    local raw_dhcp="$2"

    awk -F' \\| ' -v opt="$option_name" '
        {
            for (i = 1; i <= NF; i++) {
                split($i, pair, " = ")
                gsub(/^[ \t]+|[ \t]+$/, "", pair[1])
                gsub(/^[ \t]+|[ \t]+$/, "", pair[2])
                if (pair[1] == opt) {
                    print pair[2]
                    exit
                }
            }
        }
    ' <<< "$raw_dhcp"
}

format_lease_time() {
    local seconds="$1"
    local days
    local hours
    local minutes

    if [[ ! "$seconds" =~ ^[0-9]+$ ]]; then
        printf '%s' "$seconds"
        return
    fi

    days=$((seconds / 86400))
    hours=$(((seconds % 86400) / 3600))
    minutes=$(((seconds % 3600) / 60))

    if ((days > 0)); then
        printf '%ss (%dd %dh)' "$seconds" "$days" "$hours"
    elif ((hours > 0)); then
        printf '%ss (%dh %dm)' "$seconds" "$hours" "$minutes"
    else
        printf '%ss (%dm)' "$seconds" "$minutes"
    fi
}

format_epoch() {
    local epoch="$1"
    local formatted

    if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
        return
    fi

    if formatted="$(date -d "@$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)"; then
        printf '%s' "$formatted"
        return
    fi

    if formatted="$(date -r "$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)"; then
        printf '%s' "$formatted"
    fi
}

detect_interface() {
    local iface

    iface="$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}' || true)"
    iface="${iface%%@*}"

    if [[ -n "$iface" ]]; then
        printf '%s' "$iface"
        return
    fi

    iface="$(ip -o link show up 2>/dev/null | awk -F': ' '$2 != "lo" {print $2; exit}' || true)"
    iface="${iface%%@*}"

    printf '%s' "$iface"
}

interface_state() {
    local iface="$1"
    local state="unknown"

    if [[ -r "/sys/class/net/${iface}/operstate" ]]; then
        state="$(< "/sys/class/net/${iface}/operstate")"
    fi

    case "$state" in
        up|unknown)
            printf 'UP'
            ;;
        *)
            printf 'DOWN'
            ;;
    esac
}

interface_type() {
    local iface="$1"

    case "$iface" in
        wl*)
            printf 'wifi'
            ;;
        en*|eth*)
            printf 'ethernet'
            ;;
        lo)
            printf 'loopback'
            ;;
        *)
            printf 'network'
            ;;
    esac
}

interface_mac() {
    local iface="$1"

    if [[ -r "/sys/class/net/${iface}/address" ]]; then
        trim "$(< "/sys/class/net/${iface}/address")"
        return
    fi

    ip link show "$iface" 2>/dev/null | awk '/link\/ether/ {print $2; exit}' || true
}

read_lease_value() {
    local lease_file="$1"
    local key="$2"

    awk -F= -v key="$key" '$1 == key {print $2; exit}' "$lease_file" 2>/dev/null || true
}

collect_nmcli_details() {
    local iface="$1"
    local ip_raw
    local gateway_raw
    local dns_raw
    local dhcp_raw
    local connection_raw
    local type_raw
    local first_ip
    local cidr
    local value

    ip_raw="$(nmcli -g IP4.ADDRESS device show "$iface" 2>/dev/null || true)"
    gateway_raw="$(nmcli -g IP4.GATEWAY device show "$iface" 2>/dev/null || true)"
    dns_raw="$(nmcli -g IP4.DNS device show "$iface" 2>/dev/null || true)"
    dhcp_raw="$(nmcli -g DHCP4.OPTION device show "$iface" 2>/dev/null || true)"
    connection_raw="$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null || true)"
    type_raw="$(nmcli -g GENERAL.TYPE device show "$iface" 2>/dev/null || true)"

    value="$(normalize_list "$ip_raw" 1)"
    [[ -n "$value" ]] && IP_ADDR="$value"

    first_ip="$(first_list_item "$ip_raw")"
    if [[ "$first_ip" == */* ]]; then
        cidr="${first_ip##*/}"
        NETMASK="$(cidr_to_netmask "$cidr") (/${cidr})"
    fi

    value="$(normalize_list "$gateway_raw")"
    [[ -n "$value" ]] && GATEWAY="$value"

    value="$(normalize_list "$dns_raw")"
    [[ -n "$value" ]] && DNS="$value"

    value="$(trim "$connection_raw")"
    [[ -n "$value" && "$value" != "--" ]] && CONNECTION="$value"

    value="$(trim "$type_raw")"
    [[ -n "$value" && "$value" != "--" ]] && TYPE="$value"

    value="$(extract_dhcp_option "dhcp_server_identifier" "$dhcp_raw")"
    value="${value//\\/}"
    value="$(trim "$value")"
    [[ -n "$value" ]] && DHCP_SERVER="$value"

    value="$(extract_dhcp_option "dhcp_lease_time" "$dhcp_raw")"
    value="$(trim "$value")"
    [[ -n "$value" ]] && LEASE_TIME="$(format_lease_time "$value")"

    value="$(extract_dhcp_option "expiry" "$dhcp_raw")"
    value="$(trim "$value")"
    if [[ -n "$value" ]]; then
        value="$(format_epoch "$value")"
        [[ -n "$value" ]] && LEASE_EXPIRY="$value"
    fi
}

collect_ip_details() {
    local iface="$1"
    local ip_cidr
    local gateway_raw
    local dns_raw
    local cidr
    local value

    ip_cidr="$(ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk '{print $4; exit}' || true)"
    if [[ -n "$ip_cidr" && "$IP_ADDR" == "$NA" ]]; then
        IP_ADDR="${ip_cidr%%/*}"
    fi

    if [[ "$ip_cidr" == */* && "$NETMASK" == "$NA" ]]; then
        cidr="${ip_cidr##*/}"
        NETMASK="$(cidr_to_netmask "$cidr") (/${cidr})"
    fi

    gateway_raw="$(
        ip route show default 2>/dev/null |
            awk -v iface="$iface" '
                $1 == "default" {
                    found = 0
                    gateway = ""
                    for (i = 1; i <= NF; i++) {
                        if ($i == "dev" && $(i + 1) == iface) {
                            found = 1
                        }
                        if ($i == "via") {
                            gateway = $(i + 1)
                        }
                    }
                    if (found && gateway != "") {
                        print gateway
                        exit
                    }
                }
            ' || true
    )"
    value="$(trim "$gateway_raw")"
    [[ -n "$value" && "$GATEWAY" == "$NA" ]] && GATEWAY="$value"

    if command -v resolvectl >/dev/null 2>&1; then
        dns_raw="$(
            resolvectl dns "$iface" 2>/dev/null |
                awk -F: 'NR == 1 {gsub(/^[ \t]+/, "", $2); print $2; exit}' || true
        )"
        value="$(normalize_list "$dns_raw")"
        [[ -n "$value" && "$DNS" == "$NA" ]] && DNS="$value"
    fi

    if [[ "$DNS" == "$NA" && -r /etc/resolv.conf ]]; then
        dns_raw="$(
            awk '
                $1 == "nameserver" {
                    printf "%s%s", sep, $2
                    sep = ", "
                }
                END {
                    if (sep != "") {
                        print ""
                    }
                }
            ' /etc/resolv.conf 2>/dev/null || true
        )"
        value="$(trim "$dns_raw")"
        [[ -n "$value" ]] && DNS="$value"
    fi
}

collect_systemd_lease() {
    local iface="$1"
    local ifindex=""
    local lease_file=""
    local candidate
    local value

    if [[ -r "/sys/class/net/${iface}/ifindex" ]]; then
        ifindex="$(< "/sys/class/net/${iface}/ifindex")"
    fi

    if [[ -n "$ifindex" && -r "/run/systemd/netif/leases/${ifindex}" ]]; then
        lease_file="/run/systemd/netif/leases/${ifindex}"
    elif [[ -d /run/systemd/netif/leases ]]; then
        for candidate in /run/systemd/netif/leases/*; do
            [[ -f "$candidate" ]] || continue
            lease_file="$candidate"
            break
        done
    fi

    [[ -z "$lease_file" ]] && return 0

    value="$(read_lease_value "$lease_file" "SERVER_ADDRESS")"
    value="$(trim "$value")"
    [[ -n "$value" && "$DHCP_SERVER" == "$NA" ]] && DHCP_SERVER="$value"

    value="$(read_lease_value "$lease_file" "LIFETIME")"
    value="$(trim "$value")"
    [[ -n "$value" && "$LEASE_TIME" == "$NA" ]] && LEASE_TIME="$(format_lease_time "$value")"
}

collect_network() {
    INTERFACE="$(detect_interface)"
    debug_line "detected interface: ${INTERFACE:-None}"

    if [[ -z "$INTERFACE" ]]; then
        INTERFACE="None"
        TYPE="$NA"
        return
    fi

    STATUS="$(interface_state "$INTERFACE")"
    TYPE="$(interface_type "$INTERFACE")"
    MAC="$(interface_mac "$INTERFACE")"
    [[ -z "$MAC" ]] && MAC="$NA"

    if command -v nmcli >/dev/null 2>&1 && nmcli device show "$INTERFACE" >/dev/null 2>&1; then
        collect_nmcli_details "$INTERFACE"
    fi

    collect_ip_details "$INTERFACE"
    collect_systemd_lease "$INTERFACE"
}

truncate_value() {
    local value="$1"
    local max_width="$2"

    if ((${#value} > max_width)); then
        printf '%s...' "${value:0:$((max_width - 3))}"
    else
        printf '%s' "$value"
    fi
}

row_color() {
    local value="$1"
    local kind="${2:-value}"

    if [[ "$value" == "$NA" || "$value" == "None" ]]; then
        printf '%s' "$MUTED_COLOR"
        return
    fi

    case "$kind" in
        status)
            if [[ "$value" == "UP" ]]; then
                printf '%s' "$STATUS_UP_COLOR"
            else
                printf '%s' "$STATUS_DOWN_COLOR"
            fi
            ;;
        muted)
            printf '%s' "$MUTED_COLOR"
            ;;
        *)
            printf '%s' "$VALUE_COLOR"
            ;;
    esac
}

draw_top() {
    printf '%b┌%s┐%b\n' "$BORDER_COLOR" "$(repeat_char '─' "$((BOX_WIDTH - 2))")" "$RESET_COLOR"
}

draw_rule() {
    printf '%b├%s┤%b\n' "$BORDER_COLOR" "$(repeat_char '─' "$((BOX_WIDTH - 2))")" "$RESET_COLOR"
}

draw_bottom() {
    printf '%b└%s┘%b\n' "$BORDER_COLOR" "$(repeat_char '─' "$((BOX_WIDTH - 2))")" "$RESET_COLOR"
}

draw_title() {
    local title="$1"
    local inner_width=$((BOX_WIDTH - 2))
    local pad
    local extra

    title="$(truncate_value "$title" "$inner_width")"
    pad=$(((inner_width - ${#title}) / 2))
    extra=$(((inner_width - ${#title}) % 2))

    printf '%b│%b' "$BORDER_COLOR" "$RESET_COLOR"
    printf '%*s' "$pad" ''
    printf '%b%s%b' "$TITLE_COLOR" "$title" "$RESET_COLOR"
    printf '%*s' "$((pad + extra))" ''
    printf '%b│%b\n' "$BORDER_COLOR" "$RESET_COLOR"
}

draw_section() {
    local title="$1"
    local title_width=$((BOX_WIDTH - 4))

    title="$(truncate_value "$title" "$title_width")"
    printf '%b│%b %b%-*s%b %b│%b\n' \
        "$BORDER_COLOR" "$RESET_COLOR" \
        "$SECTION_COLOR" "$title_width" "$title" "$RESET_COLOR" \
        "$BORDER_COLOR" "$RESET_COLOR"
}

draw_blank() {
    printf '%b│%b%*s%b│%b\n' \
        "$BORDER_COLOR" "$RESET_COLOR" \
        "$((BOX_WIDTH - 2))" '' \
        "$BORDER_COLOR" "$RESET_COLOR"
}

draw_row() {
    local label="$1"
    local value="${2:-$NA}"
    local kind="${3:-value}"
    local color

    [[ -z "$value" ]] && value="$NA"
    value="$(truncate_value "$value" "$VALUE_WIDTH")"
    color="$(row_color "$value" "$kind")"

    printf '%b│%b  %b%-*s%b  %b%-*s%b  %b│%b\n' \
        "$BORDER_COLOR" "$RESET_COLOR" \
        "$LABEL_COLOR" "$LABEL_WIDTH" "$label" "$RESET_COLOR" \
        "$color" "$VALUE_WIDTH" "$value" "$RESET_COLOR" \
        "$BORDER_COLOR" "$RESET_COLOR"
}

render_panel() {
    draw_top
    draw_title "NETWORK STATUS"
    draw_rule
    draw_section "Link"
    draw_row "Interface" "$INTERFACE"
    draw_row "State" "$STATUS" "status"
    draw_row "Type" "$TYPE"
    draw_row "MAC" "$MAC"
    draw_rule
    draw_section "IPv4"
    draw_row "Connection" "$CONNECTION"
    draw_row "Address" "$IP_ADDR"
    draw_row "Netmask" "$NETMASK"
    draw_row "Gateway" "$GATEWAY"
    draw_row "DNS" "$DNS"
    draw_rule
    draw_section "DHCP"
    draw_row "Server" "$DHCP_SERVER"
    draw_row "Lease" "$LEASE_TIME"
    draw_row "Expires" "$LEASE_EXPIRY"
    draw_bottom
}

pause_if_requested() {
    ((PAUSE_ON_EXIT)) || return 0

    printf '\n%bPress Enter to close...%b' "$MUTED_COLOR" "$RESET_COLOR"
    if [[ -t 0 ]]; then
        read -r _ || true
    elif [[ -r /dev/tty ]]; then
        read -r _ < /dev/tty || true
    else
        printf '\n'
    fi
}

main() {
    local stdin_tty="no"
    local stdout_tty="no"
    local stderr_tty="no"

    parse_args "$@"
    log_invocation "$@"

    [[ -t 0 ]] && stdin_tty="yes"
    [[ -t 1 ]] && stdout_tty="yes"
    [[ -t 2 ]] && stderr_tty="yes"

    debug_line "script: $(script_path)"
    debug_line "args: $*"
    debug_line "stdin_tty=${stdin_tty} stdout_tty=${stdout_tty} stderr_tty=${stderr_tty}"
    debug_line "PATH=$PATH"
    maybe_reopen_in_terminal
    route_visible_output
    disable_colors_if_needed
    calculate_layout
    debug_line "layout width: $BOX_WIDTH"
    require_commands "ip" "awk" "date"

    if ((${DIAGNOSE_MODE:-0})); then
        diagnose
        exit 0
    fi

    collect_network
    render_panel
    pause_if_requested
    trace_line "finish interface=$INTERFACE status=$STATUS"
}

main "$@"
