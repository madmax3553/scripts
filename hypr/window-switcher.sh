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
# Script: window-switcher.sh
# Purpose: Hyprland window switcher using fuzzel
# Dependencies: fuzzel, hyprctl, jq
# Author: groot
# Modified: 2026-01-24

set -euo pipefail

icon_for() {
  case "$1" in
    *firefox*|*librewolf*) printf '' ;;
    *chrome*|*chromium*|*brave*|*vivaldi*) printf '' ;;
    *code*|*vscode*|*code-oss*) printf '󰨞' ;;
    *ghostty*|*wezterm*|*alacritty*|*kitty*|*foot*|*terminal*|*xterm*) printf '' ;;
    *thunar*|*nautilus*|*pcmanfm*|*dolphin*|*file*manager*) printf '' ;;
    *discord*) printf '' ;;
    *slack*) printf '' ;;
    *spotify*) printf '' ;;
    *steam*) printf '' ;;
    *mpv*|*vlc*) printf '' ;;
    *obsidian*|*notes*) printf '' ;;
    *pavucontrol*|*volume*|*audio*) printf '' ;;
    *qutebrowser*) printf '' ;;
    *settings*|*control*center*) printf '' ;;
    *) printf '󰖯' ;;
  esac
}

pretty_name() {
  case "$1" in
    *firefox*) printf 'Firefox' ;;
    *librewolf*) printf 'LibreWolf' ;;
    *brave*) printf 'Brave' ;;
    *chromium*) printf 'Chromium' ;;
    *chrome*) printf 'Chrome' ;;
    *vivaldi*) printf 'Vivaldi' ;;
    *code-oss*) printf 'VS Code' ;;
    *vscode*|*code*) printf 'VS Code' ;;
    *ghostty*) printf 'Ghostty' ;;
    *wezterm*) printf 'WezTerm' ;;
    *alacritty*) printf 'Alacritty' ;;
    *kitty*) printf 'Kitty' ;;
    *foot*) printf 'Foot' ;;
    *thunar*) printf 'Thunar' ;;
    *nautilus*) printf 'Files' ;;
    *pcmanfm*) printf 'PCManFM' ;;
    *dolphin*) printf 'Dolphin' ;;
    *discord*) printf 'Discord' ;;
    *slack*) printf 'Slack' ;;
    *spotify*) printf 'Spotify' ;;
    *steam*) printf 'Steam' ;;
    *mpv*) printf 'mpv' ;;
    *vlc*) printf 'VLC' ;;
    *obsidian*) printf 'Obsidian' ;;
    *pavucontrol*) printf 'Audio' ;;
    *qutebrowser*) printf 'Qutebrowser' ;;
    *settings*|*control*center*) printf 'Settings' ;;
    *)
      printf '%s' "$1" | tr '_-' '  ' | sed -E 's/(^| )([a-z])/\U\2/g'
      ;;
  esac
}

readarray -t WINDOWS < <(
  hyprctl -j clients | jq -r '
    map(select(.workspace.id >= 0 and .mapped == true)) |
    sort_by(.workspace.id, .at[0]) |
    .[] |
    [
      .address,
      (.workspace.id|tostring),
      (.workspace.name // ""),
      (.initialClass // .class // ""),
      (.class // ""),
      (.title // .initialTitle // "Untitled"),
      (.initialTitle // ""),
      (.pid|tostring)
    ] | @tsv'
)

(( ${#WINDOWS[@]} == 0 )) && exit 0

formatted=$(
  for row in "${WINDOWS[@]}"; do
    IFS=$'\t' read -r address ws_id ws_name initial_class class title initial_title pid <<< "$row"
    app_raw=${initial_class:-$class}
    app_key=$(printf '%s' "$app_raw" | tr 'A-Z' 'a-z')
    app_icon=$(icon_for "$app_key")
    app_name=$(pretty_name "$app_key")
    ws_label=${ws_name:-$ws_id}
    if [[ -n "$title" && "$title" != "$app_name" ]]; then
      label="$app_name — $title"
    else
      label="$app_name"
    fi
    display="[$ws_label] $app_icon $label"
    printf '%s\t%s\n' "$address" "$display"
  done
)

selection=$(printf '%s\n' "$formatted" | \
  fuzzel --dmenu \
       --prompt "[win] " \
       --width 50 \
       --lines 15) || exit 0

[[ -z "$selection" ]] && exit 0

address=${selection%%$'\t'*}
[[ -z "$address" ]] && exit 0

hyprctl dispatch focuswindow address:"$address"
