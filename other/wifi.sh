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
# Script: wifi.sh
# Purpose: WiFi connection manager with tofi menu
# Dependencies: nmcli, tofi, notify-send, nm-connection-editor
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

# Source common libraries
source "/home/groot/projects/scripts/lib/colors.sh"
source "/home/groot/projects/scripts/lib/common.sh"

# ===== Tofi Configuration =====

TOFI_CONFIG="${TOFI_CONFIG:-$HOME/.config/tofi/config}"

# ===== Helper Functions =====

show_menu() {
    local prompt="$1"
    local input="$2"
    printf '%b\n' "$input" | tofi --config "$TOFI_CONFIG" --prompt-text "$prompt" --ascii-input
}

show_password() {
    local ssid="$1"
    tofi --config "$TOFI_CONFIG" --prompt-text "Password for $ssid" --ascii-input --password
}

notify() {
    local title="$1"
    local message="$2"
    notify-send "$title" "$message"
}

# ===== WiFi Status Functions =====

get_wifi_status() {
    nmcli radio wifi
}

is_wifi_enabled() {
    [[ "$(get_wifi_status)" == "enabled" ]]
}

# ===== WiFi Operations =====

enable_wifi() {
    nmcli radio wifi on
    notify "WiFi" "WiFi enabled"
    sleep 1
}

disable_wifi() {
    nmcli radio wifi off
    notify "WiFi" "WiFi disabled"
}

connect_to_network() {
    if ! is_wifi_enabled; then
        log_info "WiFi disabled, enabling..."
        enable_wifi
        connect_to_network
        return
    fi
    
    # Get list of available networks
    local wifi_list
    wifi_list=$(nmcli -t -f SSID,SECURITY,SIGNAL device wifi list 2>/dev/null | \
        awk -F: '{ssid=$1; gsub(/\\:/,":",ssid); if(ssid=="") ssid="<hidden>"; printf "%s | %s | %s%%\n", ssid, $2, $3}')
    
    if [[ -z "$wifi_list" ]]; then
        log_warn "No networks found"
        notify "WiFi" "No networks available"
        return
    fi
    
    # Show menu with networks
    local chosen
    chosen=$(show_menu "WiFi Networks" "󰖪 Disable WiFi\n$wifi_list") || return
    
    if [[ -z "$chosen" ]]; then
        return
    fi
    
    if echo "$chosen" | grep -q "Disable WiFi"; then
        disable_wifi
        return
    fi
    
    # Extract SSID from the chosen line
    local ssid
    ssid=${chosen%% | *}
    if [[ "$ssid" == "<hidden>" ]]; then
        notify "WiFi" "Hidden SSID cannot be selected"
        return
    fi
    
    log_debug "Connecting to: $ssid"
    
    # Check if network requires password
    if echo "$chosen" | grep -qE "WPA|WEP|WPA2|WPA3"; then
        # Prompt for password
        local password
        password=$(show_password "$ssid") || return
        
        if [[ -z "$password" ]]; then
            log_warn "Password cancelled"
            return
        fi
        
        if nmcli device wifi connect "$ssid" password "$password" 2>/dev/null; then
            notify "WiFi" "Connected to $ssid"
            log_success "Connected to $ssid"
        else
            notify "WiFi Error" "Failed to connect to $ssid"
            log_error "Failed to connect to $ssid"
        fi
    else
        # Connect without password
        if nmcli device wifi connect "$ssid" 2>/dev/null; then
            notify "WiFi" "Connected to $ssid"
            log_success "Connected to $ssid"
        else
            notify "WiFi Error" "Failed to connect to $ssid"
            log_error "Failed to connect to $ssid"
        fi
    fi
}

open_settings() {
    log_debug "Opening WiFi settings"
    nm-connection-editor &
}

show_saved_networks() {
    # Get saved connections
    local saved
    saved=$(nmcli -f NAME connection show 2>/dev/null | tail -n +2)
    
    if [[ -z "$saved" ]]; then
        log_warn "No saved networks"
        notify "WiFi" "No saved networks found"
        return
    fi
    
    local selected
    selected=$(show_menu "Saved Networks" "$saved") || return
    
    if [[ -z "$selected" ]]; then
        return
    fi
    
    log_debug "Connecting to saved network: $selected"
    
    if nmcli connection up "$selected" 2>/dev/null; then
        notify "WiFi" "Connected to $selected"
        log_success "Connected to $selected"
    else
        notify "WiFi Error" "Failed to connect to $selected"
        log_error "Failed to connect to $selected"
    fi
}

rescan_networks() {
    log_info "Rescanning networks..."
    notify "WiFi" "Rescanning networks..."
    nmcli device wifi rescan
    sleep 2
    connect_to_network
}

disconnect_wifi() {
    log_debug "Disconnecting WiFi"
    local device
    device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2=="wifi" && $3=="connected" {print $1; exit}')
    if [[ -z "$device" ]]; then
        notify "WiFi" "No active WiFi connection"
        log_warn "No active WiFi connection"
        return
    fi
    if nmcli device disconnect "$device" 2>/dev/null; then
        notify "WiFi" "Disconnected"
        log_success "WiFi disconnected"
    else
        notify "WiFi Error" "Disconnect failed"
        log_warn "Disconnect failed"
    fi
}

show_manager_menu() {
    local choice
    choice=$(show_menu "WiFi Manager" "󰖩 WiFi Settings\n󰤨 Saved Networks\n Rescan Networks\n󰖪 Disconnect") || return
    
    case "$choice" in
        *"WiFi Settings")
            open_settings
            ;;
        *"Saved Networks")
            show_saved_networks
            ;;
        *"Rescan")
            rescan_networks
            ;;
        *"Disconnect")
            disconnect_wifi
            ;;
    esac
}

show_status() {
    if is_wifi_enabled; then
        log_info "WiFi is enabled"
        local ssid
        ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1=="yes" {print $2; exit}')
        if [[ -n "$ssid" ]]; then
            log_info "Connected to: $ssid"
        else
            log_warn "WiFi enabled but not connected"
        fi
    else
        log_warn "WiFi is disabled"
    fi
}

# ===== Help =====

usage() {
    cat << EOF
${HEADER}WiFi Connection Manager${RESET}

${BOLD}Usage:${RESET}
    wifi.sh [COMMAND]

${BOLD}Commands:${RESET}
    ${CYAN}connect${RESET}   - Connect to available network (default)
    ${CYAN}settings${RESET}  - Open WiFi settings editor
    ${CYAN}saved${RESET}     - Connect to saved network
    ${CYAN}rescan${RESET}    - Rescan available networks
    ${CYAN}disconnect${RESET} - Disconnect WiFi
    ${CYAN}manager${RESET}   - Show manager menu
    ${CYAN}status${RESET}    - Show WiFi status
    ${CYAN}help${RESET}      - Show this help message

${BOLD}Examples:${RESET}
    wifi.sh              # Connect to network (default)
    wifi.sh manager      # Full manager menu
    wifi.sh settings     # Open connection editor
    wifi.sh status       # Show current status

EOF
}

# ===== Main =====

main() {
    local cmd="${1:-connect}"
    
    case "$cmd" in
        connect)
            connect_to_network
            ;;
        settings)
            open_settings
            ;;
        saved)
            show_saved_networks
            ;;
        rescan)
            rescan_networks
            ;;
        disconnect)
            disconnect_wifi
            ;;
        manager)
            show_manager_menu
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
