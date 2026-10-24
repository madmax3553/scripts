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
# Modified: 2026-06-16

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
BOX_WIDTH="$DEFAULT_BOX_WIDTH"
VALUE_WIDTH=0
TARGET_IFACE=""
PRINT_PORTAL_URL_ONLY=0

BORDER_COLOR="$BLUE"
TITLE_COLOR="$LIGHT_CYAN"
SECTION_COLOR="$SECTION"
LABEL_COLOR="$YELLOW"
VALUE_COLOR="$LIGHT_WHITE"
MUTED_COLOR="$DIM"
STATUS_UP_COLOR="$SUCCESS"
STATUS_WARN_COLOR="$WARN"
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
SYSTEM_DNS="$NA"
DHCP_SERVER="$NA"
LEASE_TIME="$NA"
LEASE_EXPIRY="$NA"
PORTAL_STATE="$NA"
PORTAL_URL="$NA"
PORTAL_IP="$NA"

# Direct-IP HTTP probe target (Firefox detectportal Fastly anycast IP, port 80)
# Using a literal IP with a Host header triggers captive portal TCP/80
# interception without requiring system DNS resolution.
PROBE_IP="151.101.193.91"
PROBE_HOST="detectportal.firefox.com"
PROBE_PATH="/success.txt"
PROBE_EXPECTED="success"

# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [interface]

Display the active network interface, address, gateway, DNS, DHCP lease,
and captive portal status. With no interface, the one carrying the default
route is used.

Options:
  -p, --portal    Print only the captured captive portal URL (if detected)
  -n, --no-color  Disable ANSI color output
  -h, --help      Show this help

Environment:
  NETSTATUS_WIDTH  Override panel width (default: ${DEFAULT_BOX_WIDTH})
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            -p|--portal) PRINT_PORTAL_URL_ONLY=1; shift ;;
            -n|--no-color) NO_COLOR_MODE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) usage >&2; exit 1 ;;
            *) TARGET_IFACE="$1"; shift ;;
        esac
    done
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
        STATUS_WARN_COLOR=""
        STATUS_DOWN_COLOR=""
        RESET_COLOR=""
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Layout
# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────
# Parsing helpers
# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────
# Interface details
# ─────────────────────────────────────────────────────────────────────────────

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
        up|unknown) printf 'UP' ;;
        *) printf 'DOWN' ;;
    esac
}

interface_type() {
    local iface="$1"

    case "$iface" in
        wl*) printf 'wifi' ;;
        en*|eth*) printf 'ethernet' ;;
        lo) printf 'loopback' ;;
        *) printf 'network' ;;
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

# ─────────────────────────────────────────────────────────────────────────────
# Network collection
# ─────────────────────────────────────────────────────────────────────────────

collect_nmcli_details() {
    local iface="$1"
    local ip_raw gateway_raw dns_raw dhcp_raw connection_raw type_raw
    local first_ip cidr value

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

    value="$(extract_dhcp_option "captive_portal_uri" "$dhcp_raw")"
    [[ -z "$value" ]] && value="$(extract_dhcp_option "unknown_114" "$dhcp_raw")"
    value="$(trim "$value")"
    if [[ -n "$value" && "$value" =~ ^https?:// ]]; then
        PORTAL_URL="$value"
    fi
}

collect_ip_details() {
    local iface="$1"
    local ip_cidr gateway_raw dns_raw global_dns_raw cidr value

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

        global_dns_raw="$(
            resolvectl dns 2>/dev/null |
                awk -F': ' '/^Global:/ {print $2; exit}' || true
        )"
        if [[ -n "$global_dns_raw" ]]; then
            SYSTEM_DNS="$(normalize_list "${global_dns_raw// /|}")"
        elif [[ -n "$value" ]]; then
            SYSTEM_DNS="$value"
        fi
    fi

    if [[ "$DNS" == "$NA" && -r /etc/resolv.conf ]]; then
        dns_raw="$(
            awk '
                $1 == "nameserver" {
                    printf "%s%s", sep, $2
                    sep = ", "
                }
            ' /etc/resolv.conf 2>/dev/null || true
        )"
        value="$(trim "$dns_raw")"
        [[ -n "$value" ]] && DNS="$value"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Captive Portal Detection & DHCP DNS Bypass
# ─────────────────────────────────────────────────────────────────────────────

extract_url_host() {
    local url="$1"
    awk -F/ '{print $3}' <<< "$url" | cut -d: -f1
}

resolve_via_dns_server() {
    local domain="$1"
    local server="$2"

    [[ -z "$domain" || -z "$server" || "$server" == "$NA" ]] && return 0

    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "$domain"
        return 0
    fi

    command -v python3 >/dev/null 2>&1 || return 0

    python3 - "$domain" "$server" 2>/dev/null <<'PY' || true
import random, socket, struct, sys

domain, server = sys.argv[1].strip("."), sys.argv[2].strip()
tid = random.randint(0, 65535)
qname = b"".join(bytes([len(p)]) + p.encode("ascii") for p in domain.split(".")) + b"\x00"
packet = struct.pack(">HHHHHH", tid, 0x0100, 1, 0, 0, 0) + qname + struct.pack(">HH", 1, 1)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(2.0)
sock.sendto(packet, (server, 53))
data, _ = sock.recvfrom(512)
sock.close()

ancount = struct.unpack(">H", data[6:8])[0]
idx = 12
while idx < len(data) and data[idx] != 0:
    idx += 1 + data[idx]
idx += 5  # null byte + qtype + qclass

for _ in range(ancount):
    if data[idx] & 0xC0 == 0xC0:
        idx += 2
    else:
        while idx < len(data) and data[idx] != 0:
            idx += 1 + data[idx]
        idx += 1
    rtype, rclass, _, rdlen = struct.unpack(">HHIH", data[idx:idx + 10])
    idx += 10
    if rtype == 1 and rclass == 1 and rdlen == 4:
        print(socket.inet_ntoa(data[idx:idx + 4]))
        break
    idx += rdlen
PY
}

detect_captive_portal() {
    local iface="$1"
    local response headers body http_code location meta_url portal_host dhcp_dns target_ip resolved_ip

    if [[ "$STATUS" != "UP" || "$IP_ADDR" == "$NA" ]]; then
        PORTAL_STATE="OFFLINE"
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        PORTAL_STATE="$NA"
        return
    fi

    dhcp_dns="${DNS%%,*}"
    [[ "$dhcp_dns" == "$NA" || -z "$dhcp_dns" ]] && dhcp_dns="$DHCP_SERVER"
    [[ "$dhcp_dns" == "$NA" || -z "$dhcp_dns" ]] && dhcp_dns="$GATEWAY"

    # First resolve PROBE_HOST directly against the interface's DHCP DNS
    # (catches DNS-hijacking portals), falling back to PROBE_IP (catches
    # transparent TCP/80 HTTP interception without needing any DNS).
    target_ip=""
    if [[ -n "$dhcp_dns" && "$dhcp_dns" != "$NA" ]]; then
        target_ip="$(resolve_via_dns_server "$PROBE_HOST" "$dhcp_dns")"
    fi
    [[ -z "$target_ip" ]] && target_ip="$PROBE_IP"

    response="$(
        curl -s -i --interface "$iface" \
            --connect-timeout 2 -m 4 \
            -H "Host: ${PROBE_HOST}" \
            -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) CaptiveNetworkSupport" \
            "http://${target_ip}${PROBE_PATH}" 2>/dev/null || true
    )"

    if [[ -z "$response" ]]; then
        PORTAL_STATE="OFFLINE"
        return
    fi

    headers="${response%%$'\r\n\r\n'*}"
    body="${response#*$'\r\n\r\n'}"
    http_code="$(awk 'NR==1 {print $2}' <<< "$headers")"
    location="$(awk -F': ' 'tolower($1) == "location" {print $2; exit}' <<< "$headers" | tr -d '\r')"

    if [[ "$http_code" == "200" && "$(trim "$body")" == "$PROBE_EXPECTED" ]]; then
        PORTAL_STATE="CLEAR (Online)"
        PORTAL_URL="$NA"
        PORTAL_IP="$NA"
        if command -v resolvectl >/dev/null 2>&1; then
            sudo -n resolvectl revert "$iface" 2>/dev/null || true
        fi
        return
    fi

    PORTAL_STATE="DETECTED"

    if [[ -n "$location" ]]; then
        PORTAL_URL="$location"
    else
        # Some portals return 200 OK with an HTML meta-refresh or JS redirect
        meta_url="$(
            grep -oiE 'https?://[^"'\'' >]+' <<< "$body" | head -n1 || true
        )"
        if [[ -n "$meta_url" ]]; then
            PORTAL_URL="$meta_url"
        elif [[ "$PORTAL_URL" == "$NA" ]]; then
            PORTAL_URL="http://neverssl.com"
        fi
    fi

    portal_host="$(extract_url_host "$PORTAL_URL")"
    dhcp_dns="${DNS%%,*}"
    [[ "$dhcp_dns" == "$NA" || -z "$dhcp_dns" ]] && dhcp_dns="$DHCP_SERVER"
    [[ "$dhcp_dns" == "$NA" || -z "$dhcp_dns" ]] && dhcp_dns="$GATEWAY"

    if [[ -n "$portal_host" && -n "$dhcp_dns" && "$dhcp_dns" != "$NA" ]]; then
        resolved_ip="$(resolve_via_dns_server "$portal_host" "$dhcp_dns")"
        if [[ -n "$resolved_ip" ]]; then
            PORTAL_IP="${resolved_ip} (@${dhcp_dns})"
        fi
    fi

    # While behind a captive portal, hotels block external DNS (9.9.9.9) and
    # use private portal hostnames (e.g. mafod.cust.blueprintrf.com).
    # Temporarily route DNS on this interface via DHCP DNS so clicking the
    # portal URL works in the browser, and spawn a background watcher to
    # automatically revert back to Quad9 once authentication succeeds.
    if [[ -n "$dhcp_dns" && "$dhcp_dns" != "$NA" ]] && command -v resolvectl >/dev/null 2>&1; then
        if sudo -n resolvectl dns "$iface" "$dhcp_dns" 2>/dev/null; then
            sudo -n resolvectl domain "$iface" "~." 2>/dev/null || true
            sudo -n resolvectl default-route "$iface" yes 2>/dev/null || true
            sudo -n resolvectl dnsovertls "$iface" no 2>/dev/null || true
            SYSTEM_DNS="${dhcp_dns} (Portal Temp -> Quad9)"

            # Follow local controller meta-refresh / 302 redirect if present
            local hop2_body hop2_url hop3_url
            hop2_body="$(curl -s -L --interface "$iface" --connect-timeout 2 -m 4 "$PORTAL_URL" 2>/dev/null || true)"
            hop2_url="$(grep -oiE 'https?://[^"'\'' >]+' <<< "$hop2_body" | head -n1 || true)"
            if [[ -n "$hop2_url" ]]; then
                hop3_url="$(curl -s -o /dev/null -w '%{redirect_url}' --interface "$iface" --connect-timeout 2 -m 4 "$hop2_url" 2>/dev/null || true)"
                if [[ -n "$hop3_url" ]]; then
                    PORTAL_URL="$hop3_url"
                else
                    PORTAL_URL="$hop2_url"
                fi
            fi

            nohup bash -c '
                for ((i = 0; i < 150; i++)); do
                    sleep 3
                    out="$(curl -s --interface "'"$iface"'" --connect-timeout 2 -m 3 -H "Host: '"$PROBE_HOST"'" "http://'"$PROBE_IP""$PROBE_PATH"'" 2>/dev/null || true)"
                    if [[ "$out" == "'"$PROBE_EXPECTED"'" ]]; then
                        sudo -n resolvectl revert "'"$iface"'" 2>/dev/null || true
                        exit 0
                    fi
                done
                sudo -n resolvectl revert "'"$iface"'" 2>/dev/null || true
            ' </dev/null >/dev/null 2>&1 &
            disown 2>/dev/null || true
        fi
    fi
}

collect_network() {
    INTERFACE="${TARGET_IFACE:-$(detect_interface)}"

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
    detect_captive_portal "$INTERFACE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Rendering
# ─────────────────────────────────────────────────────────────────────────────

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
            if [[ "$value" == "UP" || "$value" == "CLEAR (Online)" ]]; then
                printf '%s' "$STATUS_UP_COLOR"
            elif [[ "$value" == "DETECTED" ]]; then
                printf '%s' "$STATUS_WARN_COLOR"
            else
                printf '%s' "$STATUS_DOWN_COLOR"
            fi
            ;;
        muted) printf '%s' "$MUTED_COLOR" ;;
        *) printf '%s' "$VALUE_COLOR" ;;
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
    draw_row "DHCP DNS" "$DNS"
    draw_row "System DNS" "$SYSTEM_DNS"
    draw_rule
    draw_section "DHCP"
    draw_row "Server" "$DHCP_SERVER"
    draw_row "Lease" "$LEASE_TIME"
    draw_row "Expires" "$LEASE_EXPIRY"
    draw_rule
    draw_section "Captive Portal"
    draw_row "Status" "$PORTAL_STATE" "status"
    draw_row "Portal URL" "$PORTAL_URL"
    draw_row "Portal IP" "$PORTAL_IP"
    draw_bottom

    if [[ "$PORTAL_URL" != "$NA" ]]; then
        printf '%bPortal URL:%b %s\n' "$LABEL_COLOR" "$RESET_COLOR" "$PORTAL_URL"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    disable_colors_if_needed
    calculate_layout
    require_commands "ip" "awk" "date"
    collect_network

    if ((PRINT_PORTAL_URL_ONLY)); then
        if [[ "$PORTAL_URL" != "$NA" ]]; then
            printf '%s\n' "$PORTAL_URL"
            exit 0
        fi
        exit 1
    fi

    render_panel
}

main "$@"
