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
# Script: update-timezone.sh
# Purpose: Prompt to update the system timezone from the current public IP location
# Dependencies: curl, timedatectl, sudo optional, fuzzel optional, notify-send optional
# Author: groot
# Modified: 2026-10-07

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}"
LOG_FILE="${STATE_DIR}/timezone-update.log"
LOCK_DIR="${STATE_DIR}/timezone-update.lock"
SOURCE_URL="${TIMEZONE_SOURCE_URL:-https://ipapi.co/timezone/}"
SOURCE_URLS="${TIMEZONE_SOURCE_URLS:-https://ipapi.co/timezone/ https://ipinfo.io/timezone https://worldtimeapi.org/api/ip.txt}"
TIMEOUT="${TIMEZONE_UPDATE_TIMEOUT:-6}"
OVERRIDE_TIMEZONE="${TIMEZONE_UPDATE_OVERRIDE-}"
# This site's LAN, not the company SSID. Other offices share "NOV".
# Space-separated CIDRs and/or gateway IPs. SSID alone is not enough.
TRUSTED_NETWORKS="${TIMEZONE_TRUSTED_NETWORKS:-10.114.80.0/22 10.114.80.1}"
SELECTED_TIMEZONE=""

mkdir -p "$STATE_DIR"

log() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >>"$LOG_FILE"
}

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="Timezone" "$1" "$2" >/dev/null 2>&1 || true
    fi
}

validate_timezone() {
    local timezone="$1"

    if ! [[ "$timezone" =~ ^[A-Za-z0-9._+-]+/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?$ ]]; then
        log "invalid timezone response: $timezone"
        return 1
    fi

    if [[ ! -f "/usr/share/zoneinfo/$timezone" ]]; then
        log "timezone not installed: $timezone"
        return 1
    fi

    return 0
}

extract_timezone_from_response() {
    local response="$1"
    local candidate=""

    candidate="$(printf '%s\n' "$response" | tr -d '\r' | head -n 1 | xargs)"
    if [[ "$candidate" =~ ^[A-Za-z0-9._+-]+/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?$ ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    candidate="$(printf '%s\n' "$response" | sed -nE 's/.*"timezone"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
    if [[ "$candidate" =~ ^[A-Za-z0-9._+-]+/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?$ ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    candidate="$(printf '%s\n' "$response" | sed -nE 's/^timezone:[[:space:]]*(.+)$/\1/p' | head -n 1 | xargs)"
    if [[ "$candidate" =~ ^[A-Za-z0-9._+-]+/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)?$ ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    return 1
}

detect_timezone() {
    local source="$1"
    local response=""
    local candidate=""

    if ! response="$(curl --fail --silent --show-error --location --max-time "$TIMEOUT" "$source" 2>>"$LOG_FILE")"; then
        return 1
    fi

    if ! candidate="$(extract_timezone_from_response "$response")"; then
        log "timezone source returned non-timezone payload: $source"
        return 1
    fi

    if ! validate_timezone "$candidate"; then
        log "timezone source returned invalid timezone: $source -> $candidate"
        return 1
    fi

    timezone="$candidate"
    log "timezone detected from source: $source -> $timezone"
    return 0
}

timezone_offset_minutes() {
    local timezone="$1"
    local offset
    local sign
    local hours
    local minutes
    local total

    if ! offset="$(TZ="$timezone" date +%z 2>/dev/null)"; then
        return 1
    fi

    sign="${offset:0:1}"
    hours="${offset:1:2}"
    minutes="${offset:3:2}"
    total=$((10#$hours * 60 + 10#$minutes))

    if [[ "$sign" == "-" ]]; then
        total=$((-total))
    fi

    printf '%s\n' "$total"
}

timezone_country() {
    local timezone="$1"
    local table
    local countries
    local coords
    local zone
    local rest

    for table in /usr/share/zoneinfo/zone.tab /usr/share/zoneinfo/zone1970.tab; do
        [[ -r "$table" ]] || continue

        while IFS=$'\t' read -r countries coords zone rest; do
            [[ -z "${countries:-}" || "${countries:0:1}" == "#" ]] && continue

            if [[ "$zone" == "$timezone" ]]; then
                printf '%s\n' "${countries%%,*}"
                return 0
            fi
        done <"$table"
    done

    return 1
}

find_nearby_timezone() {
    local detected="$1"
    local direction="$2"
    local detected_offset
    local country
    local region
    local table
    local countries
    local coords
    local zone
    local rest
    local offset
    local diff
    local abs_diff
    local best_zone=""
    local best_diff=0
    local best_abs=0
    local window=90

    detected_offset="$(timezone_offset_minutes "$detected")" || return 1
    country="$(timezone_country "$detected" || true)"
    region="${detected%%/*}"

    for table in /usr/share/zoneinfo/zone.tab /usr/share/zoneinfo/zone1970.tab; do
        [[ -r "$table" ]] || continue

        while IFS=$'\t' read -r countries coords zone rest; do
            [[ -z "${countries:-}" || "${countries:0:1}" == "#" ]] && continue
            [[ "$zone" == "$detected" ]] && continue
            [[ "$zone" == "$region/"* ]] || continue

            if [[ -n "$country" ]]; then
                case ",$countries," in
                *",$country,"*) ;;
                *) continue ;;
                esac
            fi

            offset="$(timezone_offset_minutes "$zone")" || continue
            diff=$((offset - detected_offset))
            abs_diff="${diff#-}"

            if [[ "$direction" == "east" ]]; then
                ((diff > 0 && diff <= window)) || continue
            else
                ((diff < 0 && abs_diff <= window)) || continue
            fi

            if [[ -z "$best_zone" ]] || ((abs_diff < best_abs)); then
                best_zone="$zone"
                best_diff="$diff"
                best_abs="$abs_diff"
            fi
        done <"$table"
    done

    [[ -n "$best_zone" ]] || return 1
    printf '%s\t%s\n' "$best_zone" "$best_diff"
}

ip_in_cidr() {
    local ip="$1"
    local cidr="$2"
    local base prefix
    local -a ip_octets base_octets
    local i shift bit ip_bit base_bit

    [[ "$cidr" == */* ]] || return 1
    base="${cidr%/*}"
    prefix="${cidr#*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] && ((prefix >= 0 && prefix <= 32)) || return 1
    [[ "$ip" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    ip_octets=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")
    [[ "$base" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    base_octets=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}")

    for i in 0 1 2 3; do
        ((ip_octets[i] <= 255 && base_octets[i] <= 255)) || return 1
        for bit in 7 6 5 4 3 2 1 0; do
            shift=$((i * 8 + (7 - bit)))
            ((shift < prefix)) || return 0
            ip_bit=$(( (ip_octets[i] >> bit) & 1 ))
            base_bit=$(( (base_octets[i] >> bit) & 1 ))
            ((ip_bit == base_bit)) || return 1
        done
    done
}

active_lan_addrs() {
    ip -4 -o addr show scope global 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4 }'
}

default_gateways() {
    ip -4 route show default 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1) }'
}

trusted_network_active() {
    local token ip gateway

    [[ -n "$TRUSTED_NETWORKS" ]] || return 1

    for token in $TRUSTED_NETWORKS; do
        if [[ "$token" == */* ]]; then
            while IFS= read -r ip; do
                [[ -n "$ip" ]] || continue
                if ip_in_cidr "$ip" "$token"; then
                    log "trusted network match: $ip in $token"
                    return 0
                fi
            done < <(active_lan_addrs)
        else
            while IFS= read -r gateway; do
                [[ "$gateway" == "$token" ]] || continue
                log "trusted network match: gateway $gateway"
                return 0
            done < <(default_gateways)
        fi
    done

    return 1
}

format_offset_delta() {
    local delta="$1"
    local abs_delta="${delta#-}"

    if ((delta > 0)); then
        printf '+%dm' "$abs_delta"
    else
        printf '%s%dm' "-" "$abs_delta"
    fi
}

build_timezone_choices() {
    local current="$1"
    local detected="$2"
    local nearby
    local zone
    local diff
    local label
    local printed="|"

    if [[ -n "$current" && -f "/usr/share/zoneinfo/$current" ]]; then
        printf '%s\tkeep current\n' "$current"
        printed="${printed}${current}|"
    fi

    if [[ "$printed" != *"|$detected|"* ]]; then
        printf '%s\tdetected\n' "$detected"
        printed="${printed}${detected}|"
    fi

    for direction in east west; do
        nearby="$(find_nearby_timezone "$detected" "$direction" || true)"
        [[ -n "$nearby" ]] || continue

        zone="${nearby%%$'\t'*}"
        diff="${nearby#*$'\t'}"
        [[ "$printed" == *"|$zone|"* ]] && continue

        label="nearby $(format_offset_delta "$diff")"
        printf '%s\t%s\n' "$zone" "$label"
        printed="${printed}${zone}|"
    done

}

select_timezone_choice() {
    local current="$1"
    local choice="$2"
    local selected

    selected="${choice%%[[:space:]]*}"
    if [[ -z "$selected" || "$selected" == "$current" ]]; then
        return 1
    fi

    if ! validate_timezone "$selected"; then
        return 1
    fi

    SELECTED_TIMEZONE="$selected"
    return 0
}

set_timezone() {
    local timezone="$1"

    if timedatectl set-timezone "$timezone" >>"$LOG_FILE" 2>&1; then
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        log "direct timedatectl failed; retrying with sudo"

        if sudo -n timedatectl set-timezone "$timezone" >>"$LOG_FILE" 2>&1; then
            return 0
        fi
    fi

    return 1
}

confirm_change() {
    local current="$1"
    local detected="$2"
    local choices
    local choice
    local choice_count
    local choice_index
    local line
    local status=0

    choices="$(build_timezone_choices "$current" "$detected")"

    if command -v fuzzel >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        choice="$(
            printf '%s\n' "$choices" |
                fuzzel --dmenu \
                    --prompt "Timezone: ${current:-unknown} -> ${detected}? " \
                    --width 54 \
                    --lines 4 \
                    --border-radius 12 \
                    --border-width 2
        )" || status=$?
        if ((status != 0)); then
            log "confirmation prompt failed or was canceled: ${current:-unknown} -> $detected (status $status)"
            return 1
        fi

        select_timezone_choice "$current" "$choice"
        return
    fi

    if [[ -t 0 ]]; then
        printf 'Timezone change detected: %s -> %s\n' "${current:-unknown}" "$detected"

        choice_count=0
        while IFS= read -r line; do
            choice_count=$((choice_count + 1))
            printf '  %d. %s\n' "$choice_count" "$line"
        done <<<"$choices"

        printf 'Select timezone [1-%d] (blank to cancel): ' "$choice_count"
        read -r choice_index

        if [[ -z "$choice_index" ]]; then
            return 1
        fi

        if ! [[ "$choice_index" =~ ^[0-9]+$ ]] || ((choice_index < 1 || choice_index > choice_count)); then
            log "invalid timezone selection: $choice_index"
            return 1
        fi

        choice_count=0
        while IFS= read -r line; do
            choice_count=$((choice_count + 1))
            if ((choice_count == choice_index)); then
                select_timezone_choice "$current" "$line"
                return
            fi
        done <<<"$choices"

        return 1
    fi

    notify "New timezone detected" "Detected ${detected}; no timezone selection UI available"
    log "confirmation unavailable: ${current:-unknown} -> $detected"
    return 1
}

cleanup() {
    rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}

if ! mkdir "$LOCK_DIR" >/dev/null 2>&1; then
    exit 0
fi
trap cleanup EXIT

if ! command -v timedatectl >/dev/null 2>&1; then
    log "missing timedatectl"
    exit 1
fi

if [[ -n "$OVERRIDE_TIMEZONE" ]]; then
    timezone="$OVERRIDE_TIMEZONE"
    log "using timezone override: $timezone"
else
    if ! command -v curl >/dev/null 2>&1; then
        log "missing curl"
        exit 1
    fi

    timezone=""

    if [[ -n "$SOURCE_URL" ]] && detect_timezone "$SOURCE_URL"; then
        :
    else
        for source in $SOURCE_URLS; do
            detect_timezone "$source" && break
        done
    fi
fi

if [[ -z "$timezone" ]]; then
    log "timezone lookup returned empty response"
    exit 1
fi

if ! validate_timezone "$timezone"; then
    exit 1
fi

current="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
if [[ "$current" == "$timezone" ]]; then
    log "timezone already current: $timezone"
    exit 0
fi

if trusted_network_active; then
    log "skipping timezone prompt on trusted network: ${current:-unknown} -> $timezone"
    exit 0
fi

notify "New timezone detected" "Detected ${timezone}; current is ${current:-unknown}"

if ! confirm_change "$current" "$timezone"; then
    log "timezone change declined: ${current:-unknown} -> $timezone"
    exit 0
fi

timezone="$SELECTED_TIMEZONE"

if set_timezone "$timezone"; then
    log "timezone updated: ${current:-unknown} -> $timezone"
    notify "Timezone updated" "$timezone"
else
    log "failed to update timezone: ${current:-unknown} -> $timezone"
    notify "Timezone update failed" "Could not set $timezone; check $LOG_FILE"
    exit 1
fi
