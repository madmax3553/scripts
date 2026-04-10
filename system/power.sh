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
set -euo pipefail

lock_session() {
  if command -v hyprlock >/dev/null 2>&1; then
    hyprlock
  elif command -v swaylock >/dev/null 2>&1; then
    swaylock
  elif command -v gtklock >/dev/null 2>&1; then
    gtklock
  elif command -v betterlockscreen >/dev/null 2>&1; then
    betterlockscreen -l
  elif command -v loginctl >/dev/null 2>&1; then
    loginctl lock-session "${XDG_SESSION_ID:-}" 2>/dev/null || loginctl lock-session
  fi
}

logout_session() {
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl dispatch exit 0
  elif command -v swaymsg >/dev/null 2>&1; then
    swaymsg exit
  elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.ksmserver /KSMServer logout 0 0 0
  elif command -v loginctl >/dev/null 2>&1; then
    if [[ -n ${XDG_SESSION_ID:-} ]]; then
      loginctl terminate-session "$XDG_SESSION_ID"
    else
      loginctl kill-user "$USER"
    fi
  fi
}

suspend_system() {
  if command -v playerctl >/dev/null 2>&1; then
    playerctl -a pause || true
  elif command -v mpc >/dev/null 2>&1; then
    mpc -q pause || true
  fi
  if command -v wpctl >/dev/null 2>&1; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ 1 || true
  elif command -v amixer >/dev/null 2>&1; then
    amixer set Master mute || true
  fi
  systemctl suspend
}

case "${1:-}" in
  lock)
    lock_session
    ;;
  exit|logout)
    logout_session
    ;;
  suspend)
    suspend_system
    ;;
  reboot)
    systemctl reboot
    ;;
  shutdown)
    systemctl poweroff
    ;;
  *)
    echo "Usage: $0 {lock|exit|suspend|reboot|shutdown}"
    exit 1
    ;;
esac
