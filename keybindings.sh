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
# Script: keybindings.sh
# Purpose: Show grouped Hyprland keybinds in fuzzel and copy a selected entry
# Dependencies: fuzzel, wl-copy
# Author: groot

set -euo pipefail

section="General"

trim() {
  local value="$1"
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

section_label() {
  printf '[%s]' "$1"
}

format_mods() {
  local mods="$1"

  mods=${mods//\$mainMod/SUPER}
  mods=${mods//SUPER/Super}
  mods=${mods//CTRL/Ctrl}
  mods=${mods//SHIFT/Shift}
  mods=${mods//ALT/Alt}

  printf '%s' "$mods" | tr ' ' '+'
}

format_key() {
  local key="$1"

  case "$key" in
    return) printf 'Enter' ;;
    left) printf 'Left' ;;
    right) printf 'Right' ;;
    up) printf 'Up' ;;
    down) printf 'Down' ;;
    space) printf 'Space' ;;
    mouse_up) printf 'WheelUp' ;;
    mouse_down) printf 'WheelDown' ;;
    XF86*) printf '%s' "$key" ;;
    mouse:272) printf 'MouseLeft' ;;
    mouse:273) printf 'MouseRight' ;;
    *) printf '%s' "$key" | tr '[:lower:]' '[:upper:]' ;;
  esac
}

describe_action() {
  local dispatcher="$1"
  local argument="$2"

  case "$dispatcher" in
    exec) printf '%s' "$argument" ;;
    workspace) printf 'Switch to workspace %s' "$argument" ;;
    movetoworkspace) printf 'Move window to workspace %s' "$argument" ;;
    togglespecialworkspace) printf 'Toggle special workspace %s' "$argument" ;;
    movefocus) case "$argument" in l) printf 'Move focus left' ;; r) printf 'Move focus right' ;; u) printf 'Move focus up' ;; d) printf 'Move focus down' ;; *) printf '%s %s' "$dispatcher" "$argument" ;; esac ;;
    fullscreen) case "$argument" in 0) printf 'Toggle fullscreen' ;; 1) printf 'Toggle maximized fullscreen' ;; *) printf '%s %s' "$dispatcher" "$argument" ;; esac ;;
    pseudo) printf 'Toggle pseudotile' ;;
    togglesplit) printf 'Toggle split orientation' ;;
    togglefloating) printf 'Toggle floating' ;;
    killactive) printf 'Close active window' ;;
    *)
      if [[ -n "$argument" ]]; then
        printf '%s %s' "$dispatcher" "$argument"
      else
        printf '%s' "$dispatcher"
      fi
      ;;
  esac
}

list_keybinds() {
  local line mods key dispatcher argument combo action

  while IFS= read -r line; do
    if [[ $line =~ ^###[[:space:]]+(.+)[[:space:]]+###$ ]]; then
      section=${BASH_REMATCH[1]}
      printf '%s\t%s\n' "__section__" "$(section_label "$section")"
      continue
    fi

    [[ $line =~ ^[[:space:]]*(bind|bindm|bindel|bindl)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
    IFS=',' read -r mods key dispatcher argument <<< "${BASH_REMATCH[2]}"
    mods=$(trim "${mods:-}")
    key=$(trim "${key:-}")
    dispatcher=$(trim "${dispatcher:-}")
    argument=${argument# }
    argument=${argument%%#*}
    argument=$(trim "$argument")

    [[ -n "$key" && -n "$dispatcher" ]] || continue

    combo=$(format_mods "$mods")
    if [[ -n "$combo" ]]; then
      combo+="+"
    fi
    combo+=$(format_key "$key")

    action=$(describe_action "$dispatcher" "$argument")
    printf '%s\t%-24s %s\n' "$section" "$combo" "$action"
  done < "$HOME/.config/hypr/configs/keybinds.conf"
}

selection=$(list_keybinds | cut -f2- | fuzzel --dmenu --prompt 'Keys> ' --width 90 --lines 24) || exit 0

[[ -z "$selection" || $selection =~ ^\[.*\]$ ]] && exit 0

printf '%s' "$selection" | wl-copy
