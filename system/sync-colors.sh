#!/usr/bin/env bash
#  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓
# ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒
#▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░
#░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░ 
#░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░ 
# ░▒   ▒ ░ ▒▓ ░▒▓░░ ░▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░   
#  ░   ░   ░▒ ░ ▒░  ░ ░ ░ ░ ░   ░ ░ ░   ░    
#░ ░   ░   ░░   ░ ░ ░ ░ ░ ░ ░ ░ ░ ░   ░      
#      ░    ░         ░ ░      ░ ░           
# Script: sync-colors.sh
# Purpose: Sync Cyberdream colorscheme across all applications
# Dependencies: python3, swaync, waybar, qt6ct
# Author: groot
# Modified: 2026-02-28

set -euo pipefail

COLORS_FILE="${HOME}/.config/colorscheme/cyberdream.json"
CONFIG_DIR="${HOME}/.config"

# Parse JSON helper
get_color() {
    python3 -c "import json; data=json.load(open('$COLORS_FILE')); print(data['colors'].get('$1', '#000000'))"
}

get_ui_color() {
    python3 -c "import json; data=json.load(open('$COLORS_FILE')); print(data['ui'].get('$1', '#000000'))"
}

BG=$(get_color "bg")
BG_ALT=$(get_color "bg_alt")
FG=$(get_color "fg")
RED=$(get_color "red")
GREEN=$(get_color "green")
YELLOW=$(get_color "yellow")
BLUE=$(get_color "blue")
MAGENTA=$(get_color "magenta")
CYAN=$(get_color "cyan")
BLACK=$(get_color "black")
ORANGE=$(get_color "orange")
PINK=$(get_color "pink")

echo "Syncing colors from $COLORS_FILE..."

# === FUZZEL ===
echo "Updating fuzzel..."
cat > "$CONFIG_DIR/fuzzel/fuzzel.ini" << FUZZEL_EOF
[main]
font=JetBrainsMono Nerd Font:size=12
dpi-aware=auto
prompt="  "
icon-theme=Papirus-Dark
icons-enabled=yes
terminal=ghostty -e
layer=overlay
exit-on-keyboard-focus-loss=yes
fields=name,generic,comment,categories,filename,keywords

width=45
horizontal-pad=12
vertical-pad=8
inner-pad=6

[colors]
background=${BG}ff
text=${FG}ff
prompt=${BLUE}ff
input=${FG}ff
match=${CYAN}ff
selection=${BG_ALT}ff
selection-text=${FG}ff
selection-match=${CYAN}ff
border=${BLUE}ff
counter=${BG_ALT}ff

[border]
width=2
radius=8

[dmenu]
exit-immediately-if-empty=yes
FUZZEL_EOF

# === SWAYNC ===
echo "Updating swaync..."
cat > "$CONFIG_DIR/swaync/style.css" << 'SWAYNC_EOF'
/* Cyberdream swaync theme */
@define-color background __BG__;
@define-color foreground __FG__;
@define-color primary __BLUE__;
@define-color primary-bright __CYAN__;
@define-color surface __BG_ALT__;
@define-color surface-variant __BG_ALT__;
@define-color error __RED__;
@define-color outline __BG_ALT__;

* {
    font-family: "Hack Nerd Font", "HackNerdFont", "Symbols Nerd Font", sans-serif;
    font-size: 14px;
}

/* Notification */
.notification {
    background: @surface;
    color: @foreground;
    border: 2px solid @outline;
    border-radius: 10px;
    padding: 10px;
    margin: 8px;
}

.body {
    color: @foreground;
}

.summary {
    font-size: 15px;
    font-weight: 700;
    background: transparent;
    color: @primary-bright;
    text-shadow: none;
}

.time {
    font-size: 13px;
    font-weight: 600;
    background: transparent;
    color: @foreground;
    text-shadow: none;
    margin-right: 15px;
}

.close-button {
    background-color: @error;
    color: @foreground;
    margin-top: 5px;
    margin-right: 5px;
    border-radius: 6px;
    border: none;
}

.close-button:hover {
    background-color: #ff8b8b;
}

.notification-default-action:hover,
.notification-action:hover {
    color: @foreground;
    background: @surface-variant;
}

.notification.critical progress {
    background-color: @error;
}

.notification.low progress,
.notification.normal progress {
    background-color: @primary;
}

/* Control Center */
.control-center {
    background-color: rgba(__BG_RGB__, 0.98);
    color: @foreground;
    border: 1px solid @outline;
    border-radius: 12px;
    padding: 10px;
}

/* Title widget */
.control-center .widget-title {
    color: @primary-bright;
    font-size: 18px;
    font-weight: bold;
    margin: 10px;
}

.control-center .widget-title > button {
    background: @surface;
    color: @foreground;
    border: 2px solid @primary;
    border-radius: 8px;
    padding: 6px 12px;
    font-size: 12px;
}

.control-center .widget-title > button:hover {
    background: @surface-variant;
    border-color: @primary-bright;
}

/* DND toggle */
.control-center .widget-dnd {
    background: @surface;
    border: 2px solid @outline;
    border-radius: 8px;
    margin: 5px;
    padding: 8px;
}

.control-center .widget-dnd > switch {
    background: @surface-variant;
    border: 1px solid @primary;
    border-radius: 12px;
}

.control-center .widget-dnd > switch:checked {
    background: @primary;
}

/* Button grid */
.control-center .widget-buttons-grid {
    padding: 5px;
    margin: 5px;
}

.control-center .widget-buttons-grid > flowbox > flowboxchild > button {
    background: @surface;
    color: @foreground;
    border: 2px solid @primary;
    border-radius: 8px;
    padding: 8px 12px;
    margin: 4px;
}

.control-center .widget-buttons-grid > flowbox > flowboxchild > button:hover {
    background: @surface-variant;
    border-color: @primary-bright;
}

/* Scrollbar */
.control-center > scrolledwindow > scrollbar {
    background: transparent;
    border-radius: 8px;
}

.control-center > scrolledwindow > scrollbar > slider {
    background: @primary;
    border-radius: 8px;
    min-width: 8px;
    min-height: 50px;
}

/* Label styling */
label {
    color: @foreground;
}

/* Buttons */
button {
    background: @surface;
    color: @foreground;
    border: 1px solid @outline;
    border-radius: 6px;
    padding: 8px 12px;
}

button:hover {
    background: @surface-variant;
    border-color: @primary;
}

/* Toggles */
switch {
    background: @surface;
    border: 1px solid @outline;
    border-radius: 12px;
}

switch:checked {
    background: @primary;
}

/* Progress bars */
progressbar {
    background: @surface;
}

progressbar > trough {
    background: @surface;
    min-height: 6px;
}

progressbar > trough > progress {
    background: @primary;
}
SWAYNC_EOF

# Replace placeholders with proper values
BG_RGB="${BG#\#}"
BG_RGB_DEC="0x${BG_RGB:0:2}, 0x${BG_RGB:2:2}, 0x${BG_RGB:4:2}"

sed -i "s|__BG__|$BG|g" "$CONFIG_DIR/swaync/style.css"
sed -i "s|__FG__|$FG|g" "$CONFIG_DIR/swaync/style.css"
sed -i "s|__BLUE__|$BLUE|g" "$CONFIG_DIR/swaync/style.css"
sed -i "s|__CYAN__|$CYAN|g" "$CONFIG_DIR/swaync/style.css"
sed -i "s|__BG_ALT__|$BG_ALT|g" "$CONFIG_DIR/swaync/style.css"
sed -i "s|__RED__|$RED|g" "$CONFIG_DIR/swaync/style.css"
sed -i "s|__BG_RGB__|$BG_RGB_DEC|g" "$CONFIG_DIR/swaync/style.css"

# === GHOSTTY ===
echo "Updating ghostty..."
cat > "$CONFIG_DIR/ghostty/config" << GHOSTTY_EOF
font-family = "Hack Nerd Font Mono"
background = $BG
foreground = $FG
cursor-color = $BLUE
cursor-text = $BG
palette = 0=#000000
palette = 1=$RED
palette = 2=$GREEN
palette = 3=$YELLOW
palette = 4=$BLUE
palette = 5=$MAGENTA
palette = 6=$CYAN
palette = 7=$FG
palette = 8=$BG_ALT
palette = 9=$RED
palette = 10=$GREEN
palette = 11=$YELLOW
palette = 12=$BLUE
palette = 13=$MAGENTA
palette = 14=$CYAN
palette = 15=$FG
GHOSTTY_EOF

# === WTFUTIL ===
echo "Updating wtfutil..."
mkdir -p "$CONFIG_DIR/wtf"
cat > "$CONFIG_DIR/wtf/config.yml" << WTF_EOF
wtf:
  colors:
    border:
      focusable: "$BG_ALT"
      focused: "$BLUE"
      normal: "$BG_ALT"
  grid:
    columns: [0, 0, 0]
    rows: [0, 0, 0, 0]
  refreshInterval: 1
  mods:
    resourceusage:
      cpuCombined: true
      enabled: true
      graphStars: 24
      position:
        top: 0
        left: 0
        height: 1
        width: 1
      refreshInterval: 2s
      showCPU: true
      showMem: true
      showSwp: false
      title: "System"
    clocks_a:
      colors:
        rows:
          even: "$BLUE"
          odd: "$FG"
      enabled: true
      locations:
        Vancouver: "America/Vancouver"
        Toronto: "America/Toronto"
      position:
        top: 0
        left: 1
        height: 1
        width: 1
      refreshInterval: 15
      sort: "alphabetical"
      title: "Clocks A"
      type: "clocks"
    clocks_b:
      colors:
        rows:
          even: "$BLUE"
          odd: "$FG"
      enabled: true
      locations:
        Paris: "Europe/Paris"
        Barcelona: "Europe/Madrid"
        Dubai: "Asia/Dubai"
      position:
        top: 0
        left: 2
        height: 1
        width: 1
      refreshInterval: 15
      sort: "alphabetical"
      title: "Clocks B"
      type: "clocks"
    nfl_news:
      enabled: true
      type: "feedreader"
      feeds:
      - https://www.espn.com/espn/rss/nfl/news
      - https://sports.yahoo.com/nfl/rss.xml
      - https://www.youtube.com/feeds/videos.xml?channel_id=UCifWD4FBa4eaKK7HLF0PlTA
      - https://blog.fantasypros.com/rss/
      feedLimit: 12
      position:
        top: 1
        left: 0
        width: 2
        height: 2
      refreshInterval: 900
      title: "NFL"
    tech_news:
      enabled: true
      type: "feedreader"
      feeds:
      - https://feeds.arstechnica.com/arstechnica/index
      - https://hnrss.org/frontpage
      feedLimit: 7
      position:
        top: 1
        left: 2
        width: 1
        height: 1
      refreshInterval: 1200
      title: "Tech"
    geopolitics:
      enabled: true
      type: "feedreader"
      feeds:
      - https://rss.dw.com/rdf/rss-en-top
      - https://www.aljazeera.com/xml/rss/all.xml
      feedLimit: 6
      position:
        top: 2
        left: 2
        width: 1
        height: 1
      refreshInterval: 1800
      title: "Geopolitics"
    ipinfo:
      colors:
        name: "$BLUE"
        value: "$FG"
      enabled: true
      position:
        top: 3
        left: 1
        height: 1
        width: 1
      refreshInterval: 150
    power:
      enabled: true
      position:
        top: 3
        left: 2
        height: 1
        width: 1
      refreshInterval: 15
      title: "⚡"
    uptime:
      args: []
      cmd: "uptime"
      enabled: true
      position:
        top: 3
        left: 0
        height: 1
        width: 1
      refreshInterval: 30
      title: "Uptime"
      type: cmdrunner
WTF_EOF

# === WAYBAR ===
echo "Updating waybar..."
cat > "$CONFIG_DIR/waybar/style.css" << WAYBAR_EOF
/*
 * Waybar stylesheet — cyberdream palette
 *
 * bg:      $BG
 * bg-alt:  $BG_ALT
 * fg:      $FG
 * red:     $RED
 * green:   $GREEN
 * yellow:  $YELLOW
 * blue:    $BLUE
 * magenta: $MAGENTA
 * cyan:    $CYAN
 */

* {
  border: none;
  border-radius: 0;
  min-height: 0;
  font-family: "Hack Nerd Font", "Hack";
  font-size: 13px;
  font-weight: bold;
  opacity: 1;
}

window#waybar {
  background-color: $BG;
  opacity: 0.9;
  transition-property: background-color;
  transition-duration: 0.5s;
}

window#waybar.hidden {
  opacity: 0.5;
}

#workspaces {
  background-color: transparent;
}

#workspaces button {
  all: initial;
  min-width: 0;
  box-shadow: inset 0 -3px transparent;
  padding: 2px 12px;
  margin: 4px 3px;
  border-radius: 4px;
  background-color: $BG_ALT;
  color: $FG;
}

#workspaces button.active {
  color: $BG;
  background-color: $BLUE;
}

#workspaces button:hover {
  box-shadow: inherit;
  text-shadow: inherit;
  color: $BG;
  background-color: $CYAN;
}

#workspaces button.urgent {
  background-color: $RED;
}

#memory,
#custom-yay,
#custom-power,
#battery,
#wireplumber,
#network,
#clock {
  border-radius: 4px;
  margin: 4px 3px;
  padding: 2px 12px;
  background-color: $BG_ALT;
  color: $BG;
}

#custom-logo {
  padding-right: 7px;
  padding-left: 7px;
  margin-left: 5px;
  font-size: 15px;
  border-radius: 8px 0px 0px 8px;
  color: $BLUE;
}

#clock {
  background-color: $MAGENTA;
}

#memory {
  background-color: $CYAN;
}

#network {
  background-color: $GREEN;
  padding-right: 17px;
}

#wireplumber {
  background-color: $BLUE;
}

#battery {
  background-color: $YELLOW;
}

#battery.warning,
#battery.critical,
#battery.urgent {
  background-color: $RED;
  color: $BG;
}

#battery.charging {
  background-color: $GREEN;
  color: $BG;
}

#custom-yay {
  background-color: $BLUE;
  color: $BG;
}

#custom-power {
  margin-right: 6px;
  background-color: $RED;
  color: $BG;
}

tooltip {
  border-radius: 8px;
  padding: 15px;
  background-color: $BG;
}

tooltip label {
  padding: 5px;
  background-color: $BG;
  color: $FG;
}

#custom-charge {
  background-color: $BG_ALT;
  margin: 4px 3px;
  padding: 2px 12px;
  border-radius: 4px;
  color: $BG;
}
#custom-charge.charging { background-color: $GREEN; color: $BG; }
#custom-charge.not_charging { background-color: $RED; color: $BG; }
#custom-charge.discharging { background-color: $RED; color: $BG; }

#custom-repostatus {
  border-radius: 4px;
  margin: 4px 3px;
  padding: 2px 12px;
  background-color: $BG;
  color: $FG;
  font-size: 18px;
  font-family: "Hack Nerd Font", "Hack";
}

#custom-repostatus.clean {
  color: $GREEN;
}

#custom-repostatus.dirty {
  color: $YELLOW;
}

#custom-repostatus.ahead {
  color: $BLUE;
}

#custom-repostatus.behind {
  color: $RED;
}

#custom-repostatus.diverged {
  color: $RED;
}

#custom-repostatus.fetch_failed {
  color: $RED;
}

#custom-repostatus.stale {
  opacity: 0.7;
}

#custom-yay.stale {
  opacity: 0.7;
}

#custom-notifications {
  border-radius: 4px;
  margin: 4px 3px;
  padding: 2px 12px;
  background-color: $CYAN;
  color: $BG;
}

#custom-notifications.notification {
  color: $BG;
}

#custom-notifications.dnd {
  background-color: $RED;
  color: $BG;
}

#custom-cliphist {
  border-radius: 4px;
  margin: 4px 3px;
  padding: 2px 12px;
  background-color: $GREEN;
  color: $BG;
}

#custom-journal {
  border-radius: 4px;
  margin: 4px 3px;
  padding: 2px 12px;
  background-color: $YELLOW;
  color: $BG;
  font-weight: bold;
}

#custom-journal:hover {
  background-color: $CYAN;
  color: $BG;
}
WAYBAR_EOF

# === QT6 ===
echo "Updating Qt6ct..."
mkdir -p "$CONFIG_DIR/qt6ct/colors"
cat > "$CONFIG_DIR/qt6ct/colors/cyberdream.conf" << QT_EOF
[ColorScheme]
AlternateBase=$BG_ALT
Base=$BG
BrightText=$FG
Button=$BG_ALT
ButtonText=$FG
Light=$BG_ALT
Link=$BLUE
LinkVisited=$MAGENTA
Highlight=$BLUE
HighlightedText=$BG
Mid=$BG_ALT
Midlight=$BG_ALT
Shadow=$BG
Text=$FG
ToolTipBase=$BG
ToolTipText=$FG
Window=$BG
WindowText=$FG
QT_EOF

# Update qt6ct.conf to use the new colorscheme
sed -i "s|color_scheme_path=.*|color_scheme_path=$CONFIG_DIR/qt6ct/colors/cyberdream.conf|" "$CONFIG_DIR/qt6ct/qt6ct.conf"

# === HYPRLAND ===
echo "Updating Hyprland..."
if [ -f ~/.config/hypr/hyprland.conf ]; then
    # Update border colors - cyan for active, bg_alt for inactive
    # Format: rgba(rrggbbaa) with hex values
    sed -i "s|col\.active_border = .*|col.active_border = rgba(${CYAN:1}ee) rgba(${MAGENTA:1}ee) 45deg|" ~/.config/hypr/hyprland.conf
    sed -i "s|col\.inactive_border = .*|col.inactive_border = rgba(${BG_ALT:1}aa)|" ~/.config/hypr/hyprland.conf
fi

# === NEOVIM ===
echo "Updating Neovim colorscheme link..."
if [ ! -d ~/.config/nvim/lua ]; then
    mkdir -p ~/.config/nvim/lua
fi
cat > ~/.config/nvim/lua/colorscheme.lua << NVIM_EOF
-- Auto-generated colorscheme - do not edit
-- Generated by sync-colors.sh

local colors = {
  bg = "$BG",
  bg_alt = "$BG_ALT",
  fg = "$FG",
  red = "$RED",
  green = "$GREEN",
  yellow = "$YELLOW",
  blue = "$BLUE",
  magenta = "$MAGENTA",
  cyan = "$CYAN",
}

-- Set colorscheme to cyberdream or fallback to default
pcall(function()
  vim.cmd("colorscheme cyberdream")
end)

-- Fallback colors if cyberdream not available
if not pcall(function() vim.cmd("colorscheme cyberdream") end) then
  vim.o.background = "dark"
  vim.cmd("highlight Normal guibg=" .. colors.bg .. " guifg=" .. colors.fg)
  vim.cmd("highlight NormalNC guibg=" .. colors.bg .. " guifg=" .. colors.fg)
  vim.cmd("highlight Visual guibg=" .. colors.blue .. " guifg=" .. colors.bg)
end
NVIM_EOF

# === SYSC-GREET ===
echo "Updating sysc-greet..."
mkdir -p "$CONFIG_DIR/sysc-greet/themes"
cat > "$CONFIG_DIR/sysc-greet/themes/groot.toml" << GREET_EOF
# groot.toml - Cyberdream theme for sysc-greet
# Auto-synced by sync-colors.sh
name = "Groot"

[colors]
bg_base = "$BG"
bg_active = "$BG_ALT"
primary = "$BLUE"
secondary = "$MAGENTA"
accent = "$CYAN"
warning = "$YELLOW"
danger = "$RED"
fg_primary = "$FG"
fg_secondary = "#cccccc"
fg_muted = "$BG_ALT"
border_focus = "$BLUE"
GREET_EOF

# === KITTY ===
echo "Updating kitty..."
cat > "$CONFIG_DIR/kitty/kitty.conf" << KITTY_EOF
font_family Hack Nerd Font
font_size 12.0
bold_font Hack Nerd Font Bold
italic_font Hack Nerd Font Italic
bold_italic_font Hack Nerd Font Bold Italic
cursor_shape block
cursor_blink_interval 0.5
cursor_underline_thickness 2
cursor_beam_thickness 2
cursor_color $BLUE
cursor_text_color $BG
background $BG
foreground $FG
background_opacity 0.9
active_tab_background   $BLUE
inactive_tab_background $BG_ALT
active_tab_foreground   $BG
inactive_tab_foreground $FG
tab_bar_background      $BG
tab_bar_foreground      $FG
selection_background    $BG_ALT
selection_foreground    $FG

# Cyberdream 16-color palette
color0  $BLACK
color1  $RED
color2  $GREEN
color3  $YELLOW
color4  $BLUE
color5  $MAGENTA
color6  $CYAN
color7  $FG
color8  $BG_ALT
color9  $RED
color10 $GREEN
color11 $YELLOW
color12 $BLUE
color13 $MAGENTA
color14 $CYAN
color15 $FG
scrollback_lines 10000
enable_audio_bell no
mouse_hide_wait 3.0
window_padding_width 10
window_padding_height 10
map ctrl+shift+c copy_to_clipboard
map ctrl+shift+v paste_from_clipboard
map ctrl+shift+t new_tab
map ctrl+shift+w close_tab
map ctrl+shift+left previous_tab
map ctrl+shift+right next_tab
KITTY_EOF

# === WLOGOUT ===
echo "Updating wlogout..."
# Convert hex BG to rgba decimal values
BG_HEX="${BG#\#}"
BG_R=$((16#${BG_HEX:0:2}))
BG_G=$((16#${BG_HEX:2:2}))
BG_B=$((16#${BG_HEX:4:2}))
BLUE_HEX="${BLUE#\#}"
BLUE_R=$((16#${BLUE_HEX:0:2}))
BLUE_G=$((16#${BLUE_HEX:2:2}))
BLUE_B=$((16#${BLUE_HEX:4:2}))
cat > "$CONFIG_DIR/wlogout/style.css" << WLOGOUT_EOF
* {
    background-image: none;
    font-size: 20px;
    font-family: "Hack Nerd Font";
}

window {
    background-color: rgba($BG_R, $BG_G, $BG_B, 0.9);
}

button {
    margin: 20px;
    color: transparent;
    background-color: transparent;
    border: none;
    outline-style: none;
    background-repeat: no-repeat;
    background-position: center;
    background-size: 20%;
    box-shadow: none;
    text-shadow: none;
    animation: gradient_f 20s ease-in infinite;
}

button:hover {
    background-color: transparent;
    background-size: 30%;
    animation: gradient_f 20s ease-in infinite;
    transition: all 0.3s cubic-bezier(.55,0.0,.28,1.682);
    outline-style: none;
}

button:active {
    background-color: rgba($BLUE_R, $BLUE_G, $BLUE_B, 0.4);
    box-shadow: 0 0 40px rgba($BLUE_R, $BLUE_G, $BLUE_B, 0.8);
    outline-style: none;
}

#lock {
    background-image: image(url("icons/lock.png"));
}

#logout {
    background-image: image(url("icons/logout.png"));
}

#suspend {
    background-image: image(url("icons/suspend.png"));
}

#shutdown {
    background-image: image(url("icons/shutdown.png"));
}

#reboot {
    background-image: image(url("icons/reboot.png"));
}

#hibernate {
    background-image: image(url("icons/hibernate.png"));
}
WLOGOUT_EOF

# === REMMINA ===
echo "Updating remmina..."
cat > "$CONFIG_DIR/remmina/remmina.colors" << REMMINA_EOF
[ssh_colors]
background = $BG
cursor = $BLUE
cursor_foreground = $BG
foreground = $FG
highlight = $BG_ALT
highlight_foreground = $FG
color0 = $BLACK
color1 = $RED
color2 = $GREEN
color3 = $YELLOW
color4 = $BLUE
color5 = $MAGENTA
color6 = $CYAN
color7 = $FG
color8 = $BG_ALT
color9 = $RED
color10 = $GREEN
color11 = $YELLOW
color12 = $BLUE
color13 = $MAGENTA
color14 = $CYAN
color15 = $FG
colorBD = $FG
colorIT =
colorUL =
REMMINA_EOF

# === STARSHIP ===
echo "Updating starship..."
# Starship uses $variable syntax in its format strings, so we can't use heredoc.
# Instead, do targeted sed replacements on hex color values.
if [ -f "$CONFIG_DIR/starship.toml" ]; then
    # Update fg/white color references (used for distro, username)
    sed -i "s|(\#[0-9a-fA-F]\{6\}) '|(${FG}) '|g" "$CONFIG_DIR/starship.toml"
    # Update yellow color references (used for hostname, device)
    sed -i "s|\[\$hostname\](#[0-9a-fA-F]\{6\})|\[\$hostname](${YELLOW})|" "$CONFIG_DIR/starship.toml"
    sed -i "s|\[\$env_value\](#[0-9a-fA-F]\{6\})'$|\[\$env_value](${YELLOW})'|" "$CONFIG_DIR/starship.toml"
    # Update green color references (git branch, git status, staged)
    sed -i "s|bold #[0-9a-fA-F]\{6\}\"|bold ${GREEN}\"|g" "$CONFIG_DIR/starship.toml"
    sed -i "s|\](#[0-9a-fA-F]\{6\})'$|](${GREEN})'|" "$CONFIG_DIR/starship.toml"
fi

echo ""
echo "To apply changes:"
echo "  - Swaync will update on next notification"
echo "  - Hyprland: run 'hyprctl reload' to apply border colors"
echo "  - Neovim: restart or run ':colorscheme cyberdream'"
echo "  - sysc-greet: select 'Groot' theme via F1 menu"
echo "  - Kitty: close and reopen terminal"
echo "  - Waybar: run 'killall -SIGUSR2 waybar' to reload"
echo "  - Starship: opens new shell to apply"
echo "  - Restart other applications (fuzzel, ghostty, wlogout, remmina)"
