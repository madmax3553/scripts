#!/usr/bin/env bash
# Script: tzdata-waybar-fix.sh
# Purpose: Temporary tzdata rollback with auto-expiring hold for Waybar clock regression
# Dependencies: pacman, systemctl, date, curl
# Author: groot
# Modified: 2026-07-11

set -euo pipefail

PACMAN_CONF="/etc/pacman.conf"
STATE_DIR="/var/lib/tzdata-waybar-fix"
STATE_FILE="${STATE_DIR}/state.env"
TIMER_UNIT="tzdata-waybar-unhold.timer"
SERVICE_UNIT="tzdata-waybar-unhold.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_UNIT}"
TIMER_PATH="/etc/systemd/system/${TIMER_UNIT}"

HOLD_BEGIN="# BEGIN TEMP_TZDATA_HOLD_WAYBAR"
HOLD_END="# END TEMP_TZDATA_HOLD_WAYBAR"

DEFAULT_VERSION="2026b-1"
DEFAULT_DAYS="14"
SCRIPT_PATH="$(readlink -f "$0")"

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "This script must be run as root." >&2
        exit 1
    fi
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") apply [--version 2026b-1] [--days 14] [--time 10:00:00]
  $(basename "$0") unhold
  $(basename "$0") status

Commands:
  apply   Roll back tzdata, add temporary IgnorePkg hold, and schedule auto-unhold timer
  unhold  Remove temporary hold and remove timer/service units
  status  Show current tzdata version and hold/timer status
EOF
}

remove_hold_block() {
    if [[ ! -f "${PACMAN_CONF}" ]]; then
        return 0
    fi

    awk -v begin="${HOLD_BEGIN}" -v end="${HOLD_END}" '
        $0 == begin { skip=1; next }
        $0 == end { skip=0; next }
        skip != 1 { print }
    ' "${PACMAN_CONF}" >"${PACMAN_CONF}.tmp"

    mv "${PACMAN_CONF}.tmp" "${PACMAN_CONF}"
}

add_hold_block() {
    local expires_on="$1"

    remove_hold_block

    awk -v begin="${HOLD_BEGIN}" -v end="${HOLD_END}" -v expires="${expires_on}" '
        BEGIN { inserted=0 }
        {
            print
            if (!inserted && $0 ~ /^#IgnoreGroup[[:space:]]*=/) {
                print ""
                print begin
                print "# Temporary hold for Waybar clock/tzdata regression."
                print "# Expires: " expires
                print "IgnorePkg = tzdata"
                print end
                inserted=1
            }
        }
        END {
            if (!inserted) {
                print ""
                print begin
                print "# Temporary hold for Waybar clock/tzdata regression."
                print "# Expires: " expires
                print "IgnorePkg = tzdata"
                print end
            }
        }
    ' "${PACMAN_CONF}" >"${PACMAN_CONF}.tmp"

    mv "${PACMAN_CONF}.tmp" "${PACMAN_CONF}"
}

write_service_unit() {
    cat >"${SERVICE_PATH}" <<EOF
[Unit]
Description=Remove temporary tzdata hold for Waybar clock fix

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} unhold
EOF
}

write_timer_unit() {
    local calendar="$1"

    cat >"${TIMER_PATH}" <<EOF
[Unit]
Description=Auto-expire temporary tzdata hold for Waybar clock fix

[Timer]
OnCalendar=${calendar}
Persistent=true
Unit=${SERVICE_UNIT}

[Install]
WantedBy=timers.target
EOF
}

download_or_find_pkg() {
    local version="$1"
    local pkg_name="tzdata-${version}-x86_64.pkg.tar.zst"
    local cache_pkg="/var/cache/pacman/pkg/${pkg_name}"
    local local_pkg="/tmp/${pkg_name}"
    local archive_url="https://archive.archlinux.org/packages/t/tzdata/${pkg_name}"

    if [[ -f "${cache_pkg}" ]]; then
        printf '%s\n' "${cache_pkg}"
        return 0
    fi

    curl --fail --location --silent --show-error --output "${local_pkg}" "${archive_url}"
    printf '%s\n' "${local_pkg}"
}

apply_fix() {
    local version="${DEFAULT_VERSION}"
    local days="${DEFAULT_DAYS}"
    local expire_time="10:00:00"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                version="${2:-}"
                shift 2
                ;;
            --days)
                days="${2:-}"
                shift 2
                ;;
            --time)
                expire_time="${2:-}"
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    if ! [[ "${days}" =~ ^[0-9]+$ ]]; then
        echo "--days must be an integer." >&2
        exit 1
    fi

    local expires_on
    local on_calendar
    local pkg_path

    expires_on="$(date -d "+${days} days" +%Y-%m-%d)"
    on_calendar="${expires_on} ${expire_time}"

    pkg_path="$(download_or_find_pkg "${version}")"

    pacman -U --noconfirm "${pkg_path}"
    add_hold_block "${expires_on}"

    mkdir -p "${STATE_DIR}"
    cat >"${STATE_FILE}" <<EOF
TZDATA_TARGET=${version}
EXPIRES_ON=${expires_on}
ON_CALENDAR=${on_calendar}
SCRIPT_PATH=${SCRIPT_PATH}
EOF

    write_service_unit
    write_timer_unit "${on_calendar}"

    systemctl daemon-reload
    systemctl enable --now "${TIMER_UNIT}"

    echo "Applied tzdata rollback to ${version}."
    echo "Temporary hold enabled and will auto-expire at: ${on_calendar}."
    echo "Current tzdata: $(pacman -Q tzdata | awk '{print $2}')"
}

unhold_fix() {
    remove_hold_block

    systemctl disable --now "${TIMER_UNIT}" >/dev/null 2>&1 || true
    rm -f "${TIMER_PATH}" "${SERVICE_PATH}"
    systemctl daemon-reload

    rm -f "${STATE_FILE}" >/dev/null 2>&1 || true
    rmdir "${STATE_DIR}" >/dev/null 2>&1 || true

    echo "Temporary tzdata hold removed."
    echo "Current tzdata: $(pacman -Q tzdata | awk '{print $2}')"
}

status_fix() {
    echo "tzdata version: $(pacman -Q tzdata | awk '{print $2}')"

    if rg -q "^${HOLD_BEGIN}$" "${PACMAN_CONF}" 2>/dev/null; then
        echo "Hold in pacman.conf: enabled"
    else
        echo "Hold in pacman.conf: disabled"
    fi

    if systemctl list-timers --all | rg -q "${TIMER_UNIT}"; then
        systemctl list-timers --all | rg "${TIMER_UNIT}" || true
    else
        echo "Auto-expire timer: not scheduled"
    fi

    if [[ -f "${STATE_FILE}" ]]; then
        echo "--- state ---"
        cat "${STATE_FILE}"
    fi
}

main() {
    local cmd="${1:-status}"
    shift || true

    case "${cmd}" in
        apply)
            require_root
            apply_fix "$@"
            ;;
        unhold)
            require_root
            unhold_fix
            ;;
        status)
            status_fix
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo "Unknown command: ${cmd}" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
