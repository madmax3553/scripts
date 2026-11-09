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
# Script: netmon.sh
# Purpose: Home Network NOC Terminal Monitor - display all LAN nodes with latency and status
# Dependencies: ping, tput, timeout
# Author: groot
# Modified: 2026-09-27

set -uo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Data Arrays
# ─────────────────────────────────────────────────────────────────────────────

declare -a NODE_IPS
declare -a NODE_NAMES
declare -a NODE_CATEGORIES
declare -a NODE_ONLINE
declare -a NODE_LAST_RTT
declare -a NODE_SENT
declare -a NODE_RECEIVED
declare -a NODE_HISTORY
declare -a WORKER_PIDS
declare -a NODE_RESULT_SEQ
declare -a NODE_DIRTY
declare -a NODE_NAME_LOOKED_UP
declare -a DISPLAY_NODE
declare -a DISPLAY_GROUP
RESULT_DIR=""
DISCOVERY_PID=""
DISCOVERY_SEQ=0
DISCOVERY_PREFIX="${NETMON_DISCOVERY_PREFIX:-10.69.69}"
DNS_PID=""
DNS_RESULT_SEQ=0
DNS_TESTED=0
DNS_ONLINE=0
DNS_AVAILABLE=0
TERM_HEIGHT=${LINES:-24}
TERM_WIDTH=${COLUMNS:-80}
DEVICE_WIDTH=25
RESIZE_PENDING=0
SCREEN_ACTIVE=0

# ─────────────────────────────────────────────────────────────────────────────
# Colors (from project standards)
# ─────────────────────────────────────────────────────────────────────────────

export RED=$'\033[0;31m'
export GREEN=$'\033[0;32m'
export YELLOW=$'\033[1;33m'
export CYAN=$'\033[0;36m'
export MAGENTA=$'\033[0;35m'
export WHITE=$'\033[0;37m'
export BLACK=$'\033[0;30m'
export BOLD=$'\033[1m'
export DIM=$'\033[2m'
export RESET=$'\033[0m'
export INVERSE=$'\033[7m'

# ─────────────────────────────────────────────────────────────────────────────
# Node Management Functions
# ─────────────────────────────────────────────────────────────────────────────

add_node() {
    local ip=$1
    local name=$2
    local category=$3
    NODE_IPS+=("$ip")
    NODE_NAMES+=("$name")
    NODE_CATEGORIES+=("$category")
    NODE_ONLINE+=(0)
    NODE_LAST_RTT+=(0)
    NODE_SENT+=(0)
    NODE_RECEIVED+=(0)
    NODE_HISTORY+=("")
}

init_nodes() {
    # ─────────────────────────────────────────────────────────────────────────
    # Public DNS / WAN probes
    add_node "1.1.1.1" "Cloudflare DNS (WAN)" "WAN"
    add_node "8.8.8.8" "Google DNS (WAN)" "WAN"
    add_node "9.9.9.9" "Quad9 DNS (Preferred)" "WAN"

    # ─────────────────────────────────────────────────────────────────────────
    # Infrastructure
    add_node "10.69.69.254" "Gateway / Fiber Router" "Infra"
    add_node "10.69.69.20" "Wi-Fi Mesh Pod #1" "Infra"
    add_node "10.69.69.21" "Wi-Fi Mesh Pod #2" "Infra"
    add_node "10.69.69.22" "Wi-Fi Mesh Pod #3" "Infra"
    add_node "10.69.69.225" "iGarchy (DHCP / DNS)" "Infra"

    # ─────────────────────────────────────────────────────────────────────────
    # Smart Home & IoT
    add_node "10.69.69.182" "Nest Thermostat (HVAC)" "IoT"
    add_node "10.69.69.80" "Reolink Security Cam" "IoT"
    add_node "10.69.69.154" "Kitchen Nest Hub" "IoT"
    add_node "10.69.69.156" "Bedroom Nest Mini" "IoT"
    add_node "10.69.69.116" "Living Room Google Home" "IoT"
    add_node "10.69.69.162" "Living Room Speaker" "IoT"

    # ─────────────────────────────────────────────────────────────────────────
    # Entertainment & Gaming
    add_node "10.69.69.93" "Sony Bravia 4K TV (65\")" "Media"
    add_node "10.69.69.141" "PlayStation 4 (PS4-8034F5)" "Media"
    add_node "10.69.69.104" "Nintendo Switch #1" "Media"
    add_node "10.69.69.120" "Nintendo Switch #2" "Media"

    # ─────────────────────────────────────────────────────────────────────────
    # Workstation & Clients
    add_node "10.69.69.222" "Arch Workstation (Local)" "Host"
    add_node "10.69.69.52" "Apple Device (.52)" "Client"
    add_node "10.69.69.85" "Apple Device (.85)" "Client"
    add_node "10.69.69.142" "Apple Device (.142)" "Client"
    add_node "10.69.69.160" "Apple Device (.160)" "Client"
    add_node "10.69.69.150" "Mobile Device (Random)" "Client"

}

# ─────────────────────────────────────────────────────────────────────────────
# Ping & Monitoring Functions
# ─────────────────────────────────────────────────────────────────────────────

ping_host() {
    local idx=$1
    local ip="${NODE_IPS[$idx]}"
    local t0=$(date +%s%N)

    if ping -c 1 -W 1 "$ip" &>/dev/null; then
        local t1=$(date +%s%N)
        local rtt=$(( (t1 - t0) / 1000000 ))
        NODE_LAST_RTT[$idx]=$rtt
        NODE_ONLINE[$idx]=1
    else
        NODE_LAST_RTT[$idx]=0
        NODE_ONLINE[$idx]=0
    fi
}

record_result() {
    local idx=$1
    ((NODE_SENT[$idx] += 1))

    if [[ ${NODE_ONLINE[$idx]} -eq 1 ]]; then
        ((NODE_RECEIVED[$idx] += 1))
    fi

    # Append to history
    local history_value=${NODE_LAST_RTT[$idx]}
    if [[ ${NODE_ONLINE[$idx]} -eq 0 ]]; then
        history_value="x"
    fi
    NODE_HISTORY[$idx]+="${history_value} "

    # Keep only last 12 entries
    local history_array=(${NODE_HISTORY[$idx]})
    if [[ ${#history_array[@]} -gt 12 ]]; then
        NODE_HISTORY[$idx]="${history_array[@]:${#history_array[@]}-12}"
    fi
}

get_loss_pct() {
    local idx=$1
    local sent=${NODE_SENT[$idx]:-0}
    local received=${NODE_RECEIVED[$idx]:-0}

    if [[ $sent -eq 0 ]]; then
        echo "0"
    else
        echo $(( (sent - received) * 100 / sent ))
    fi
}

get_sparkline() {
    local idx=$1
    local history=(${NODE_HISTORY[$idx]})
    local -a chars=( "░" "▂" "▃" "▒" "▅" "▆" "▓" "█" )
    local spark=""

    if [[ ${#history[@]} -eq 0 ]]; then
        echo "        "
        return
    fi

    # Get last 8 values
    local start=$(( ${#history[@]} > 8 ? ${#history[@]} - 8 : 0 ))
    for ((i=${#history[@]}-start; i<8; i++)); do
        spark+=" "
    done
    for ((i=start; i<${#history[@]}; i++)); do
        local sample=${history[$i]}
        if [[ ! $sample =~ ^[0-9]+$ ]]; then
            spark+="${RED}×${CYAN}"
        else
            local val=$((10#$sample))
            local level=$((val * 7 / 100))
            ((level > 7)) && level=7
            spark+="${chars[$level]}"
        fi
    done

    printf '%s%s%s' "$CYAN" "$spark" "$RESET"
}

read_terminal_size() {
    if [[ -t 1 ]]; then
        TERM_HEIGHT=$(tput lines 2>/dev/null || printf '24')
        TERM_WIDTH=$(tput cols 2>/dev/null || printf '80')
    fi
    DEVICE_WIDTH=$((TERM_WIDTH - 49))
    ((DEVICE_WIDTH > 25)) && DEVICE_WIDTH=25
    ((DEVICE_WIDTH < 8)) && DEVICE_WIDTH=8
}

move_cursor() {
    printf '\033[%d;%dH' "$(( $1 + 1 ))" "$(( $2 + 1 ))"
}

clear_to_eol() {
    printf '\033[K'
}

worker_thread() {
    local idx=$1
    local ip="${NODE_IPS[$idx]}"
    local sequence=0
    local result_file="${RESULT_DIR}/${idx}"
    local temp_file="${result_file}.tmp"
    local online rtt t0 t1

    while true; do
        t0=$(date +%s%N)
        if ping -c 1 -W 1 "$ip" &>/dev/null; then
            t1=$(date +%s%N)
            rtt=$(( (t1 - t0) / 1000000 ))
            online=1
        else
            rtt=0
            online=0
        fi
        ((sequence += 1))
        printf '%s %s %s\n' "$sequence" "$online" "$rtt" > "$temp_file"
        mv -f -- "$temp_file" "$result_file"
        sleep 1
    done
}

collect_worker_results() {
    local idx sequence online rtt
    for ((idx=0; idx<${#NODE_IPS[@]}; idx++)); do
        [[ -r "${RESULT_DIR}/${idx}" ]] || continue
        read -r sequence online rtt < "${RESULT_DIR}/${idx}" || continue
        [[ "$sequence" =~ ^[0-9]+$ && "$online" =~ ^[01]$ && "$rtt" =~ ^[0-9]+$ ]] || continue
        if [[ ${NODE_RESULT_SEQ[$idx]:-0} -ne $sequence ]]; then
            NODE_RESULT_SEQ[$idx]=$sequence
            NODE_ONLINE[$idx]=$online
            NODE_LAST_RTT[$idx]=$rtt
            record_result "$idx"
            NODE_DIRTY[$idx]=1
        fi
    done
}

dns_probe_worker() {
    local result_file="${RESULT_DIR}/dns"
    local temp_file="${result_file}.tmp"
    local sequence=0
    local online

    while true; do
        if timeout 3 getent ahostsv4 example.com >/dev/null 2>&1; then
            online=1
        else
            online=0
        fi
        ((sequence += 1))
        printf '%s %s\n' "$sequence" "$online" > "$temp_file"
        mv -f -- "$temp_file" "$result_file"
        sleep 5
    done
}

collect_dns_result() {
    local sequence online
    local result_file="${RESULT_DIR}/dns"
    [[ -r "$result_file" ]] || return 0
    read -r sequence online < "$result_file" || return 0
    [[ "$sequence" =~ ^[0-9]+$ && "$online" =~ ^[01]$ ]] || return 0
    [[ "$sequence" -ne "$DNS_RESULT_SEQ" ]] || return 0
    DNS_RESULT_SEQ=$sequence
    DNS_ONLINE=$online
    DNS_TESTED=1
}

scan_network() {
    local scan_file="${RESULT_DIR}/discovered"
    local temp_file="${scan_file}.new"
    local sequence=0
    local host batch_end host_in_batch ip pid
    local -a scan_pids

    while true; do
        ((sequence += 1))
        printf '%s\n' "$sequence" > "$temp_file"

        for ((host=1; host<255; host+=32)); do
            batch_end=$((host + 32))
            ((batch_end > 255)) && batch_end=255
            scan_pids=()

            for ((host_in_batch=host; host_in_batch<batch_end; host_in_batch++)); do
                ip="${DISCOVERY_PREFIX}.${host_in_batch}"
                ping -n -c 1 -W 1 "$ip" &>/dev/null && printf '%s\n' "$ip" >> "$temp_file" &
                scan_pids+=("$!")
            done

            for pid in "${scan_pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done
        done

        mv -f -- "$temp_file" "$scan_file"
        sleep 60
    done
}

collect_discovered_nodes() {
    local ip sequence host_num idx
    local -a scan_results
    local scan_file="${RESULT_DIR}/discovered"

    [[ -r "$scan_file" ]] || return 0
    mapfile -t scan_results < "$scan_file"
    sequence=${scan_results[0]:-0}
    [[ "$sequence" =~ ^[0-9]+$ ]] || return 0
    [[ "$sequence" -ne "$DISCOVERY_SEQ" ]] || return 0
    DISCOVERY_SEQ=$sequence

    for ((result_index=1; result_index<${#scan_results[@]}; result_index++)); do
        ip=${scan_results[$result_index]}
        [[ "${ip%.*}" == "$DISCOVERY_PREFIX" ]] || continue
        host_num=${ip##*.}
        [[ "$host_num" =~ ^[0-9]+$ ]] || continue
        ((10#$host_num >= 1 && 10#$host_num <= 254)) || continue

        local known=0
        for ((idx=0; idx<${#NODE_IPS[@]}; idx++)); do
            if [[ "${NODE_IPS[$idx]}" == "$ip" ]]; then
                known=1
                break
            fi
        done
        ((known == 1)) && continue

        add_node "$ip" "Discovered device" "Discovered"
        idx=$((${#NODE_IPS[@]} - 1))
        NODE_RESULT_SEQ[$idx]=0
        NODE_DIRTY[$idx]=1
        NODE_NAME_LOOKED_UP[$idx]=0
        worker_thread "$idx" </dev/null &
        WORKER_PIDS+=("$!")
    done
}

resolve_node_names() {
    local idx ip hostname
    local -a lookup_candidates=()

    command -v getent >/dev/null 2>&1 || return 0

    for ((idx=0; idx<${#NODE_IPS[@]}; idx++)); do
        [[ ${NODE_NAME_LOOKED_UP[$idx]:-0} -eq 1 ]] && continue
        # Keep configured descriptive labels, but replace generic labels with
        # a PTR name when the local DHCP/DNS service publishes one.
        case "${NODE_NAMES[$idx]}" in
            "Apple Device ("*|"Discovered device") ;;
            *) continue ;;
        esac
        lookup_candidates+=("$idx")
    done

    # Resolve in the background so name service latency never blocks a screen
    # refresh. Each eligible node is queued only once, even when lookup fails.
    for idx in "${lookup_candidates[@]}"; do
        NODE_NAME_LOOKED_UP[$idx]=1
        ip=${NODE_IPS[$idx]}
        {
            hostname=$(timeout 1 getent hosts "$ip" 2>/dev/null | awk 'NR == 1 { print $2; exit }')
            [[ -n "$hostname" ]] || exit 0
            printf '%s\n' "$hostname" > "${RESULT_DIR}/name.${idx}.tmp"
            mv -f -- "${RESULT_DIR}/name.${idx}.tmp" "${RESULT_DIR}/name.${idx}"
        } </dev/null >/dev/null 2>&1 &
    done
}

collect_node_names() {
    local idx hostname result_file
    for ((idx=0; idx<${#NODE_IPS[@]}; idx++)); do
        result_file="${RESULT_DIR}/name.${idx}"
        [[ -r "$result_file" ]] || continue
        hostname=$(<"$result_file")
        [[ -n "$hostname" && "${NODE_NAMES[$idx]}" != "$hostname" ]] || continue
        NODE_NAMES[$idx]=$hostname
        NODE_DIRTY[$idx]=1
        rm -f -- "$result_file"
    done
}

build_display_rows() {
    local idx category group previous_group=""
    DISPLAY_NODE=()
    DISPLAY_GROUP=()

    for ((idx=0; idx<${#NODE_IPS[@]}; idx++)); do
        category=${NODE_CATEGORIES[$idx]}
        case "$category" in
            Infra) group="INFRASTRUCTURE" ;;
            IoT) group="SMART HOME & IOT" ;;
            Media) group="ENTERTAINMENT & GAMING" ;;
            Host|Client) group="WORKSTATION & CLIENTS" ;;
            WAN) group="PUBLIC DNS / WAN" ;;
            Discovered) group="DISCOVERED DEVICES" ;;
            *) group="OTHER DEVICES" ;;
        esac

        if [[ "$group" != "$previous_group" ]]; then
            DISPLAY_NODE+=("")
            DISPLAY_GROUP+=("$group")
            previous_group=$group
        fi
        DISPLAY_NODE+=("$idx")
        DISPLAY_GROUP+=("")
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Display Functions
# ─────────────────────────────────────────────────────────────────────────────

draw_ui() {
    local scroll_offset=$1
    local force_rows=${2:-0}
    local i
    local height=$TERM_HEIGHT
    local width=$TERM_WIDTH

    if ((width < 57 || height < 6)); then
        if [[ -t 1 ]]; then
            move_cursor 0 0
            clear_to_eol
        fi
        printf '%sTerminal too small: need at least 57 columns × 6 rows.%s' "$YELLOW" "$RESET"
        return
    fi

    # Count up/down
    local up_count=0
    local down_count=0
    local wan_up=0
    local wan_tested=0
    local wan_total=0
    for ((i=0; i<${#NODE_IPS[@]}; i++)); do
        if [[ ${NODE_CATEGORIES[$i]} == WAN ]]; then
            ((wan_total += 1))
        fi
        if [[ ${NODE_ONLINE[$i]:-0} -eq 1 ]]; then
            ((up_count += 1))
            [[ ${NODE_CATEGORIES[$i]} == WAN ]] && ((wan_up += 1))
        else
            ((down_count += 1))
        fi
        if [[ ${NODE_CATEGORIES[$i]} == WAN && ${NODE_SENT[$i]:-0} -gt 0 ]]; then
            ((wan_tested += 1))
        fi
    done

    # Title bar
    local title="◈ NETMON / HOME NETWORK OPS"
    local time_str=$(date +"%H:%M:%S")
    local status_line="${#NODE_IPS[@]} nodes  |  ${up_count} up  |  ${down_count} down"
    local dns_status="DNS N/A"
    if ((DNS_AVAILABLE)); then
        dns_status="DNS CHECKING"
    fi
    if ((DNS_AVAILABLE && DNS_TESTED)); then
        if ((DNS_ONLINE)); then
            dns_status="DNS OK"
        else
            dns_status="DNS FAIL"
        fi
    fi
    local wan_status="WAN CHECKING"
    if ((wan_up > 0)); then
        wan_status="WAN ${wan_up}/${wan_total}"
    elif ((wan_total > 0 && wan_tested == wan_total)); then
        wan_status="WAN DOWN"
    fi
    local right_info="${time_str}  ${dns_status}  ${wan_status}"
    local title_width=$((width - ${#right_info} - 2))
    ((title_width < 1)) && title_width=1
    local title_line="${title:0:title_width}"
    printf -v title_line '%-*s  %s' "$title_width" "$title_line" "$right_info"

    if [[ -t 1 ]]; then
        move_cursor 0 0
        clear_to_eol
    fi
    printf '%s' "${BOLD}${CYAN}${title_line}${RESET}"

    # Visible node and group rows
    local max_rows=$((height - 5))
    ((max_rows < 1)) && max_rows=1
    local view_index node_idx group_name row
    for ((view_index=scroll_offset; view_index<scroll_offset + max_rows && view_index<${#DISPLAY_NODE[@]}; view_index++)); do
        node_idx=${DISPLAY_NODE[$view_index]:-}
        group_name=${DISPLAY_GROUP[$view_index]:-}
        if [[ -z "$node_idx" && -n "$group_name" && $force_rows -eq 0 ]]; then
            continue
        fi
        if [[ -n "$node_idx" && $force_rows -eq 0 && ${NODE_DIRTY[$node_idx]:-0} -eq 0 ]]; then
            continue
        fi
        row=$((view_index - scroll_offset + 3))
        if [[ -t 1 ]]; then
            move_cursor "$row" 0
            clear_to_eol
        fi

        if [[ -n "$group_name" ]]; then
            printf '%s── %s ──%s' "${BOLD}${CYAN}" "$group_name" "$RESET"
            continue
        fi

        i=$node_idx
        local status="UP"
        local status_color="$GREEN"

        if [[ ${NODE_ONLINE[$i]:-0} -eq 0 ]]; then
            status="DOWN"
            status_color="$RED"
        fi

        local rtt_text=$(printf "%5.1f ms" "${NODE_LAST_RTT[$i]:-0}")
        local rtt_color="$GREEN"

        if [[ ${NODE_ONLINE[$i]:-0} -eq 0 ]]; then
            rtt_text="   --   "
            rtt_color="$RED"
        elif (( ${NODE_LAST_RTT[$i]:-0} > 80 )); then
            rtt_color="$YELLOW"
        fi

        local loss_pct=$(get_loss_pct "$i")
        local loss_text=$(printf "%5d%%" "$loss_pct")
        local loss_color="$GREEN"
        if (( loss_pct > 0 )); then
            loss_color="$RED"
        fi

        local spark=$(get_sparkline "$i")
        printf '%s' "${status_color}${BOLD}"
        printf '  %-5s' "$status"
        printf '%s' "$RESET"
        printf ' %-15s %-*s' "${NODE_IPS[$i]}" "$DEVICE_WIDTH" "${NODE_NAMES[$i]}"
        printf '%s' "$rtt_color"
        printf ' %8s' "$rtt_text"
        printf '%s ' "$RESET"
        printf '%s' "$spark"
        printf '%s' "$loss_color"
        printf ' %6s' "$loss_text"
        printf '%s' "$RESET"
        NODE_DIRTY[$i]=0
    done

    # Footer
    local footer="↑/↓ scroll  ·  q quit  ·  ${status_line}"
    if [[ -t 1 ]]; then
        move_cursor "$((height - 1))" 0
        clear_to_eol
    fi
    printf '%s' "${DIM}$(printf "%-$((width-1))s" "$footer")${RESET}"
}

draw_static_ui() {
    read_terminal_size
    local height=$TERM_HEIGHT
    local width=$TERM_WIDTH
    if [[ -t 1 ]]; then
        tput clear
    fi

    local header
    if ((width < 57 || height < 6)); then
        printf '\033[1;1H\033[K%sTerminal too small: need at least 57 columns × 6 rows.%s' \
            "$YELLOW" "$RESET"
        return
    fi
    printf -v header '  %-5s %-15s %-*s %8s %-8s %6s' \
        "STATE" "ADDRESS" "$DEVICE_WIDTH" "DEVICE" "RTT" "HISTORY" "LOSS"
    printf '\033[2;1H\033[K%s' "${BOLD}${WHITE}${header}${RESET}"
    printf '\033[3;1H\033[K'
    local rule
    printf -v rule '%*s' "$((width-1))" ''
    rule=${rule// /─}
    printf '%s' "$rule"
    for ((row=3; row<height; row++)); do
        move_cursor "$row" 0
        clear_to_eol
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup & Main Loop
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
    if [[ -n "${original_settings:-}" ]]; then
        stty "$original_settings" 2>/dev/null || true
    fi
    if [[ $SCREEN_ACTIVE -eq 1 ]]; then
        printf '\033[0m\033[?25h\033[?1049l'
        SCREEN_ACTIVE=0
    fi
    if ((${#WORKER_PIDS[@]} > 0)); then
        kill "${WORKER_PIDS[@]}" 2>/dev/null || true
        wait "${WORKER_PIDS[@]}" 2>/dev/null || true
    fi
    if [[ -n "${DISCOVERY_PID:-}" ]]; then
        kill "$DISCOVERY_PID" 2>/dev/null || true
        wait "$DISCOVERY_PID" 2>/dev/null || true
    fi
    if [[ -n "${DNS_PID:-}" ]]; then
        kill "$DNS_PID" 2>/dev/null || true
        wait "$DNS_PID" 2>/dev/null || true
    fi
    if [[ -n "$RESULT_DIR" && -d "$RESULT_DIR" ]]; then
        rm -rf -- "$RESULT_DIR"
    fi
}

main() {
    if ! command -v ping >/dev/null 2>&1; then
        printf 'netmon: ping is required\n' >&2
        exit 1
    fi

    init_nodes
    build_display_rows
    RESULT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/netmon.XXXXXX") || {
        printf 'netmon: could not create a temporary result directory\n' >&2
        exit 1
    }
    NODE_RESULT_SEQ=()
    NODE_DIRTY=()
    NODE_NAME_LOOKED_UP=()
    for ((i=0; i<${#NODE_IPS[@]}; i++)); do
        NODE_DIRTY[$i]=1
        NODE_NAME_LOOKED_UP[$i]=0
    done

    # Start worker threads
    for ((i=0; i<${#NODE_IPS[@]}; i++)); do
        worker_thread "$i" </dev/null &
        WORKER_PIDS+=($!)
    done
    scan_network </dev/null >/dev/null 2>&1 &
    DISCOVERY_PID=$!
    if command -v timeout >/dev/null 2>&1 && command -v getent >/dev/null 2>&1; then
        dns_probe_worker </dev/null >/dev/null 2>&1 &
        DNS_PID=$!
        DNS_AVAILABLE=1
    fi
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    local scroll_offset=0

    # Enable raw terminal mode (only if interactive)
    if [[ -t 0 ]]; then
        original_settings=$(stty -g)
        stty -icanon -echo min 0 time 0
    else
        original_settings=""
    fi
    if [[ -t 1 ]]; then
        printf '\033[?1049h\033[?25l'
        SCREEN_ACTIVE=1
        draw_static_ui
    fi
    trap 'RESIZE_PENDING=1' WINCH

    local last_draw_second=0
    local force_rows=1

    # Main loop
    while true; do
        # Handle keyboard input (only if interactive terminal)
        if [[ -t 0 ]]; then
            local key=""
            if read -r -s -t 0.1 -n 1 key 2>/dev/null; then
                case "$key" in
                    q|Q)
                        break
                        ;;
                    $'\x1b')
                        local seq=""
                        read -r -s -t 0.05 -n 2 seq 2>/dev/null || true
                        case "$seq" in
                            '[A')
                                if ((scroll_offset > 0)); then
                                    ((scroll_offset -= 1))
                                    force_rows=1
                                fi
                                ;;
                            '[B')
                                local visible_rows=$((TERM_HEIGHT - 5))
                                ((visible_rows < 1)) && visible_rows=1
                                local max_scroll=$((${#DISPLAY_NODE[@]} - visible_rows))
                                ((max_scroll < 0)) && max_scroll=0
                                if ((scroll_offset < max_scroll)); then
                                    ((scroll_offset += 1))
                                    force_rows=1
                                fi
                                ;;
                        esac
                        ;;
                esac
            fi
        fi

        if ((RESIZE_PENDING)); then
            RESIZE_PENDING=0
            draw_static_ui
            force_rows=1
            local resized_max_scroll=$((${#DISPLAY_NODE[@]} - (TERM_HEIGHT - 5)))
            ((resized_max_scroll < 0)) && resized_max_scroll=0
            ((scroll_offset > resized_max_scroll)) && scroll_offset=$resized_max_scroll
        fi

        # Ping results change about once per second; avoid repainting identical frames.
        collect_discovered_nodes
        resolve_node_names
        collect_node_names
        build_display_rows
        collect_worker_results
        collect_dns_result
        local current_second
        current_second=$(date +%s)
        local dirty_visible=0
        local visible_rows=$((TERM_HEIGHT - 5))
        ((visible_rows < 1)) && visible_rows=1
        for ((i=scroll_offset; i<scroll_offset + visible_rows && i<${#DISPLAY_NODE[@]}; i++)); do
            local node_idx=${DISPLAY_NODE[$i]:-}
            if [[ -n "$node_idx" && ${NODE_DIRTY[$node_idx]:-0} -eq 1 ]]; then
                dirty_visible=1
                break
            fi
        done
        if [[ "$current_second" -ne "$last_draw_second" || $dirty_visible -eq 1 || $force_rows -eq 1 ]]; then
            draw_ui "$scroll_offset" "$force_rows"
            force_rows=0
            last_draw_second=$current_second
        fi

    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────────────────────────────

main "$@"
