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
# Update color palette comments (non-breaking)
sed -i "s/^.*bg:      #[0-9a-fA-F]*/# * bg:      $BG/" "$CONFIG_DIR/waybar/style.css"
sed -i "s/^.*bg-alt:  #[0-9a-fA-F]*/# * bg-alt:  $BG_ALT/" "$CONFIG_DIR/waybar/style.css"
sed -i "s/^.*fg:      #[0-9a-fA-F]*/# * fg:      $FG/" "$CONFIG_DIR/waybar/style.css"

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

echo "✓ Colors synced successfully!"
echo ""
echo "Colors used:"
echo "  Background:  $BG"
echo "  Background (alt): $BG_ALT"
echo "  Foreground:  $FG"
echo "  Blue (accent): $BLUE"
echo "  Cyan: $CYAN"
echo ""
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

echo ""
echo "To apply changes:"
echo "  - Swaync will update on next notification"
echo "  - Hyprland: run 'hyprctl reload' to apply border colors"
echo "  - Neovim: restart or run ':colorscheme cyberdream'"
echo "  - Restart other applications (fuzzel, ghostty, etc.)"
