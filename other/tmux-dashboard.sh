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
# Script: tmux-dashboard.sh
# Purpose: Launch a tmux-based terminal dashboard
# Dependencies: tmux, python3, curl
# Author: groot
# Modified: 2026-03-14

set -euo pipefail

source "/home/groot/projects/scripts/lib/common.sh"

ansi() {
    printf '%b' "$1"
}

hex_to_ansi() {
    local hex="$1"
    hex="${hex#\#}"
    printf '[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

load_dashboard_palette() {
    local palette_file="${HOME}/.config/colorscheme/cyberdream.json"
    local palette_values

    if [[ ! -f "$palette_file" ]]; then
        palette_file="/home/groot/dotfiles/colorscheme/.config/colorscheme/cyberdream.json"
    fi

    if [[ -f "$palette_file" ]]; then
        palette_values="$(python3 - "$palette_file" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)
colors = data.get('colors', {})
print(colors.get('fg', '#ffffff'))
print(colors.get('bg_alt', '#3c4048'))
print(colors.get('red', '#ff6e5e'))
print(colors.get('green', '#5eff6c'))
print(colors.get('yellow', '#f1ff5e'))
print(colors.get('blue', '#5ea1ff'))
print(colors.get('magenta', '#bd5eff'))
print(colors.get('cyan', '#5ef1ff'))
print(colors.get('orange', '#ff9e3e'))
print(colors.get('pink', '#ff79c6'))
PY
)"
        mapfile -t _palette <<< "$palette_values"
        DASH_FG_HEX="${_palette[0]}"
        DASH_MUTED_HEX="${_palette[1]}"
        DASH_RED_HEX="${_palette[2]}"
        DASH_GREEN_HEX="${_palette[3]}"
        DASH_YELLOW_HEX="${_palette[4]}"
        DASH_BLUE_HEX="${_palette[5]}"
        DASH_MAGENTA_HEX="${_palette[6]}"
        DASH_CYAN_HEX="${_palette[7]}"
        DASH_ORANGE_HEX="${_palette[8]}"
        DASH_PINK_HEX="${_palette[9]}"
    else
        DASH_FG_HEX="#ffffff"
        DASH_MUTED_HEX="#3c4048"
        DASH_RED_HEX="#ff6e5e"
        DASH_GREEN_HEX="#5eff6c"
        DASH_YELLOW_HEX="#f1ff5e"
        DASH_BLUE_HEX="#5ea1ff"
        DASH_MAGENTA_HEX="#bd5eff"
        DASH_CYAN_HEX="#5ef1ff"
        DASH_ORANGE_HEX="#ff9e3e"
        DASH_PINK_HEX="#ff79c6"
    fi

    DASH_FG="$(hex_to_ansi "$DASH_FG_HEX")"
    DASH_MUTED="$(hex_to_ansi "$DASH_MUTED_HEX")"
    DASH_RED="$(hex_to_ansi "$DASH_RED_HEX")"
    DASH_GREEN="$(hex_to_ansi "$DASH_GREEN_HEX")"
    DASH_YELLOW="$(hex_to_ansi "$DASH_YELLOW_HEX")"
    DASH_BLUE="$(hex_to_ansi "$DASH_BLUE_HEX")"
    DASH_MAGENTA="$(hex_to_ansi "$DASH_MAGENTA_HEX")"
    DASH_CYAN="$(hex_to_ansi "$DASH_CYAN_HEX")"
    DASH_ORANGE="$(hex_to_ansi "$DASH_ORANGE_HEX")"
    DASH_PINK="$(hex_to_ansi "$DASH_PINK_HEX")"
    DASH_RESET="$(ansi "$RESET")"
    DASH_DIM="$(ansi "$DIM")"
}

load_dashboard_palette

SESSION_NAME="${TMUX_DASHBOARD_SESSION:-dashboard}"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REPOSTATUS_PATH="/home/groot/projects/scripts/repostatus"
NEWS_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-dashboard"
NEWS_CACHE_FILE="$NEWS_CACHE_DIR/news.json"
NEWS_FEEDS=(
    "https://www.cbsnews.com/latest/rss/main/"
    "https://thehill.com/news/rss"
    "https://www.straightarrow.news/feed"
    "https://feeds.foxnews.com/foxnews/latest"
    "https://www.espn.com/espn/rss/news"
)

CLOCK_NAMES=(
    "Dubai"
    "UTC"
    "Newfoundland"
    "New York"
    "Houston"
    "Edmonton"
    "California"
    "Anchorage"
)

CLOCK_ZONES=(
    "Asia/Dubai"
    "UTC"
    "America/St_Johns"
    "America/New_York"
    "America/Chicago"
    "America/Edmonton"
    "America/Los_Angeles"
    "America/Anchorage"
)

usage() {
    cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  launch                Create or attach to the dashboard session
  launch-detached       Create the dashboard session without attaching
  open-story <number>   Open a cached article in the browser
  menu stories          Pick and open a cached article via fuzzel/dmenu
  menu repos            Run repo actions via fuzzel/dmenu
  pane <name>           Run a pane renderer loop
  render <name>         Render pane output once
  help                  Show this help
EOF
}

ensure_cache_dir() {
    mkdir -p "$NEWS_CACHE_DIR"
}

update_news_cache() {
    ensure_cache_dir
    python3 - "$NEWS_CACHE_FILE" "${NEWS_FEEDS[@]}" <<'PY'
import html
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

output_path = sys.argv[1]
feeds = sys.argv[2:]

stories = []
seen = set()
source_counts = {}

def clean(text):
    text = html.unescape(text or "")
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()

def extract_link(entry):
    node = entry.find("link")
    if node is not None:
        href = node.attrib.get("href")
        if href:
            return href.strip()
        if node.text:
            return node.text.strip()

    for atom_link in entry.findall("{http://www.w3.org/2005/Atom}link"):
        href = atom_link.attrib.get("href")
        rel = atom_link.attrib.get("rel", "alternate")
        if href and rel == "alternate":
            return href.strip()

    guid = entry.find("guid")
    if guid is not None and guid.text and guid.text.startswith("http"):
        return guid.text.strip()

    return ""

for url in feeds:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "tmux-dashboard/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = resp.read()
        root = ET.fromstring(data)
    except Exception:
        continue

    channel_title = "Feed"
    channel = root.find("channel")
    if channel is not None:
        title_node = channel.find("title")
        if title_node is not None and title_node.text:
            channel_title = clean(title_node.text)

    entries = root.findall(".//item")
    if not entries:
        entries = root.findall(".//{http://www.w3.org/2005/Atom}entry")

    for entry in entries:
        title_node = entry.find("title")
        if title_node is None:
            title_node = entry.find("{http://www.w3.org/2005/Atom}title")

        summary_node = entry.find("description")
        if summary_node is None:
            summary_node = entry.find("summary")
        if summary_node is None:
            summary_node = entry.find("{http://www.w3.org/2005/Atom}summary")

        title = clean(title_node.text if title_node is not None else "")
        summary = clean(summary_node.text if summary_node is not None else "")
        link = extract_link(entry)
        if not title or title in seen:
            continue

        count = source_counts.get(channel_title, 0)
        if count >= 3:
            continue

        seen.add(title)
        source_counts[channel_title] = count + 1
        stories.append(
            {
                "source": channel_title,
                "title": title,
                "summary": summary or "No summary available.",
                "link": link,
            }
        )

        if len(stories) >= 20:
            break

    if len(stories) >= 20:
        break

payload = {
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "stories": stories,
}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY
}

read_news_cache_json() {
    ensure_cache_dir

    if [[ ! -s "$NEWS_CACHE_FILE" ]]; then
        update_news_cache
    elif [[ $(( $(date +%s) - $(stat -c %Y "$NEWS_CACHE_FILE" 2>/dev/null || echo 0) )) -ge 300 ]]; then
        update_news_cache
    fi

    if [[ ! -s "$NEWS_CACHE_FILE" ]]; then
        printf '{"updated_at":"","stories":[]}'
        return
    fi

    python3 - "$NEWS_CACHE_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {"updated_at": "", "stories": []}

print(json.dumps(data))
PY
}

open_story() {
    local story_index="${1:-}"
    if [[ ! "$story_index" =~ ^[0-9]+$ ]]; then
        die "Story number must be numeric"
    fi

    local news_json
    news_json="$(read_news_cache_json)"

    local story_url
    story_url="$(NEWS_JSON="$news_json" python3 - "$story_index" <<'PY'
import json
import os
import sys

index = int(sys.argv[1]) - 1
data = json.loads(os.environ.get("NEWS_JSON", "{}"))
stories = data.get("stories", [])

if 0 <= index < len(stories):
    print(stories[index].get("link", ""))
PY
)"

    if [[ -z "$story_url" ]]; then
        die "No cached article for story $story_index"
    fi

    if command -v xdg-open >/dev/null 2>&1; then
        nohup xdg-open "$story_url" >/dev/null 2>&1 &
    else
        python3 -m webbrowser "$story_url" >/dev/null 2>&1 &
    fi

    printf 'Opened story %s: %s\n' "$story_index" "$story_url"
}

show_dmenu() {
    local prompt="$1"
    local lines="$2"

    if command -v fuzzel >/dev/null 2>&1; then
        fuzzel --dmenu --prompt "$prompt" --lines "$lines"
        return
    fi

    if command -v rofi >/dev/null 2>&1; then
        rofi -dmenu -p "$prompt"
        return
    fi

    die "Need fuzzel or rofi for menu support"
}

story_menu() {
    local news_json selected story_url
    news_json="$(read_news_cache_json)"

    selected="$(NEWS_JSON="$news_json" python3 - <<'PY' | show_dmenu "Story" 12 || true
import json
import os
from urllib.parse import urlparse

def short_link(url):
    if not url:
        return ""
    parsed = urlparse(url)
    host = parsed.netloc.replace("www.", "")
    path = parsed.path.rstrip("/")
    if path:
        parts = [p for p in path.split("/") if p][:2]
        path = "/" + "/".join(parts)
    return f"{host}{path}" if host else url

data = json.loads(os.environ.get("NEWS_JSON", "{}"))
for idx, story in enumerate(data.get("stories", [])[:20], start=1):
    title = story.get("title", "")
    source = story.get("source", "Feed")
    link = short_link(story.get("link", ""))
    text = f"[{idx}] {title}"
    if source:
        text += f" - {source}"
    if link:
        text += f" [{link}]"
    print(text)
PY
)"

    [[ -z "$selected" ]] && return 0

    story_url="$(NEWS_JSON="$news_json" SELECTED_STORY="$selected" python3 - <<'PY'
import json
import os
import re

selected = os.environ.get("SELECTED_STORY", "")
match = re.search(r"\[(\d+)\]", selected)
if not match:
    raise SystemExit(0)

index = int(match.group(1)) - 1
data = json.loads(os.environ.get("NEWS_JSON", "{}"))
stories = data.get("stories", [])
if 0 <= index < len(stories):
    print(stories[index].get("link", ""))
PY
)"

    [[ -z "$story_url" ]] && return 0

    if command -v xdg-open >/dev/null 2>&1; then
        nohup xdg-open "$story_url" >/dev/null 2>&1 &
    else
        python3 -m webbrowser "$story_url" >/dev/null 2>&1 &
    fi
}

repo_menu() {
    local selected
    selected="$(printf '%s\n' \
        'Refresh repo pane' \
        'Open git window' \
        'Sync all repos' \
        'Sync all repos in git window' | show_dmenu "Repos" 8 || true)"

    [[ -z "$selected" ]] && return 0

    case "$selected" in
        'Refresh repo pane')
            if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                tmux respawn-pane -k -t "$SESSION_NAME:home.5" "$(tmux_pane_command repo)"
            fi
            ;;
        'Open git window')
            if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                tmux select-window -t "$SESSION_NAME:git"
            fi
            ;;
        'Sync all repos')
            if [[ -n "${TMUX:-}" ]] && tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                tmux new-window -t "$SESSION_NAME" -n sync-repos "exec bash -lc '$REPOSTATUS_PATH --sync; printf \"\\nPress Enter to close...\"; read -r'"
            else
                "$REPOSTATUS_PATH" --sync
            fi
            ;;
        'Sync all repos in git window')
            if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                tmux respawn-pane -k -t "$SESSION_NAME:git.0" "exec bash -lc '$REPOSTATUS_PATH --sync; printf \"\\nPress Enter to reopen repostatus...\"; read -r; exec $REPOSTATUS_PATH'"
                tmux select-window -t "$SESSION_NAME:git"
            fi
            ;;
    esac
}

tmux_pane_command() {
    local pane_name="$1"
    printf 'exec %q pane %q' "$SCRIPT_PATH" "$pane_name"
}

attach_dashboard() {
    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$SESSION_NAME"
    else
        tmux attach-session -t "$SESSION_NAME"
    fi
}

run_or_fallback_monitor() {
    if command -v btm >/dev/null 2>&1; then
        exec btm
    elif command -v htop >/dev/null 2>&1; then
        exec htop
    else
        exec top
    fi
}

run_or_fallback_monitor_compact() {
    if command -v btm >/dev/null 2>&1; then
        exec btm --basic
    elif command -v htop >/dev/null 2>&1; then
        exec htop
    else
        exec top
    fi
}

run_or_fallback_newsboat() {
    if command -v newsboat >/dev/null 2>&1; then
        exec newsboat
    fi

    while true; do
        clear
        printf 'newsboat is not installed.\n\n'
        printf 'Install it to use the interactive feeds window.\n'
        sleep 30
    done
}

run_or_fallback_repostatus() {
    if [[ -x "$REPOSTATUS_PATH" ]]; then
        exec "$REPOSTATUS_PATH"
    elif command -v repostatus >/dev/null 2>&1; then
        exec repostatus
    fi

    while true; do
        clear
        printf 'repostatus is not available.\n'
        sleep 30
    done
}

render_header() {
    local title="$1"
    printf '%b%s%b\n' "$DASH_CYAN" "$title" "$DASH_RESET"
    printf '%b%*s%b\n\n' "$DASH_MUTED" "${#title}" '' "$DASH_RESET" | tr ' ' '-'
}

render_ticker() {
    local news_json
    news_json="$(read_news_cache_json)"

    NEWS_JSON="$news_json" python3 - <<'PY'
import html
from urllib.parse import urlparse
import json
import os

data = json.loads(os.environ.get("NEWS_JSON", "{}"))
stories = data.get("stories", [])
items = []

def clean(text):
    return html.unescape(" ".join((text or "").split())).strip()

def short_link(url):
    if not url:
        return ""
    parsed = urlparse(url)
    host = parsed.netloc.replace("www.", "")
    path = parsed.path.rstrip("/")
    if path:
        parts = [p for p in path.split("/") if p][:2]
        path = "/" + "/".join(parts)
    return f"{host}{path}" if host else url

for idx, story in enumerate(stories[:12], start=1):
    title = clean(story.get("title", ""))
    source = clean(story.get("source", "Feed"))
    link = story.get("link", "")
    if not title:
        continue
    if link:
        items.append(f"{idx}. {source}: {title} [{short_link(link)}]")
    else:
        items.append(f"{idx}. {source}: {title}")

if not items:
    print("No headlines available right now.")
else:
    print(" | ".join(items))
PY
}

run_ticker_loop() {
    local ticker_text sports_text width ticker_offset=0 sports_offset=0 refresh_counter=0

    pad_line() {
        local text="$1"
        local target_width="$2"
        printf '%-*.*s' "$target_width" "$target_width" "$text"
    }

    center_line() {
        local text="$1"
        local target_width="$2"
        local text_width=${#text}
        local left_pad=0
        if (( target_width > text_width )); then
            left_pad=$(((target_width - text_width) / 2))
        fi
        printf '%*s%s' "$left_pad" '' "$text"
    }

    fill_pattern() {
        local target_width="$1"
        local pattern="$2"
        local output=""

        while (( ${#output} < target_width )); do
            output+="$pattern"
        done

        printf '%s' "${output:0:target_width}"
    }

    header_line() {
        local target_width="$1"
        local title='[= GROOTWARE PRESENTS :: DASHBOARD 64 =]'
        local inner_width left_fill right_fill

        if (( target_width <= ${#title} + 2 )); then
            printf '%s' "$(pad_line "$title" "$target_width")"
            return
        fi

        inner_width=$((target_width - ${#title} - 2))
        left_fill=$((inner_width / 2))
        right_fill=$((inner_width - left_fill))

        printf '%s %s%s' \
            "$(fill_pattern "$left_fill" '=~')" \
            "$title" \
            "$(fill_pattern "$right_fill" '~=')"
    }

    while true; do
        if [[ $refresh_counter -le 0 || -z "${ticker_text:-}" || -z "${sports_text:-}" ]]; then
            ticker_text="$(render_ticker)"
            sports_text="$(render_sports_compact)"
            refresh_counter=300
        fi

        width=$(tput cols 2>/dev/null || printf '80')
        width=$((width > 2 ? width - 1 : width))

        mapfile -t ticker_lines < <(TICKER_TEXT="$ticker_text" TICKER_WIDTH="$width" TICKER_OFFSET="$ticker_offset" python3 - <<'PY'
import os

text = os.environ.get("TICKER_TEXT", "")
width = max(int(os.environ.get("TICKER_WIDTH", "80")), 20)
offset = int(os.environ.get("TICKER_OFFSET", "0"))

if not text:
    text = "No headlines available right now."

padding = "   ***   "
scroll_text = text + padding + text + padding
start = offset % (len(text) + len(padding))
window = scroll_text[start:start + width]
print(window)
PY
)

        mapfile -t sports_lines < <(SPORTS_TEXT="$sports_text" SPORTS_WIDTH="$width" SPORTS_OFFSET="$sports_offset" python3 - <<'PY'
import os

text = os.environ.get("SPORTS_TEXT", "")
width = max(int(os.environ.get("SPORTS_WIDTH", "80")), 20)
offset = int(os.environ.get("SPORTS_OFFSET", "0"))

if not text:
    text = "No scores available."

padding = "   ***   "
scroll_text = text + padding + text + padding
start = offset % (len(text) + len(padding))
window = scroll_text[start:start + width]
print(window)
PY
        )

        printf '\033[H'
        printf '%b%s%b\n\n' "$DASH_PINK" "$(header_line "$width")" "$DASH_RESET"
        printf '%b%s%b\n' "$DASH_CYAN" "$(pad_line "${ticker_lines[0]:-No headlines available right now.}" "$width")" "$DASH_RESET"
        printf '%b%s%b\n' "$DASH_ORANGE" "$(pad_line "${sports_lines[0]:-No scores available.}" "$width")" "$DASH_RESET"
        printf '%s\n' "$(pad_line "$(render_clocks_line)" "$width")"
        printf '%b%s%b' "$DASH_MUTED" "$(pad_line "Super+B dashboard  Super+N stories  Super+Shift+R repos" "$width")" "$DASH_RESET"

        ticker_offset=$((ticker_offset + 1))
        sports_offset=$((sports_offset + 1))
        refresh_counter=$((refresh_counter - 1))
        sleep 0.12
    done
}

render_clocks_line() {
    CLOCK_COLOR="$DASH_BLUE" LOCAL_COLOR="$DASH_GREEN" RESET_COLOR="$DASH_RESET" python3 - <<'PY'
from datetime import datetime
import os
from pathlib import Path
from zoneinfo import ZoneInfo

clocks = [
    ("Dubai", "Asia/Dubai"),
    ("UTC", "UTC"),
    ("Newfoundland", "America/St_Johns"),
    ("NewYork", "America/New_York"),
    ("Houston", "America/Chicago"),
    ("Edmonton", "America/Edmonton"),
    ("California", "America/Los_Angeles"),
    ("Anchorage", "America/Anchorage"),
]

default_color = os.environ.get("CLOCK_COLOR", "")
local_color = os.environ.get("LOCAL_COLOR", "")
reset = os.environ.get("RESET_COLOR", "")

def detect_local_timezone():
    tz_env = os.environ.get("TZ")
    if tz_env:
        return tz_env

    localtime = Path("/etc/localtime")
    try:
        resolved = localtime.resolve()
        parts = resolved.parts
        if "zoneinfo" in parts:
            idx = parts.index("zoneinfo")
            return "/".join(parts[idx + 1:])
    except Exception:
        pass

    return None

local_zone = detect_local_timezone()
zones = [zone for _, zone in clocks]
if local_zone and local_zone not in zones:
    local_label = local_zone.rsplit("/", 1)[-1].replace("_", " ")
    clocks.append((f"Local:{local_label}", local_zone))

parts = []
for name, tz_name in clocks:
    now = datetime.now(ZoneInfo(tz_name))
    text = f"{name} {now.strftime('%H:%M')}"
    color = local_color if local_zone and tz_name == local_zone else default_color
    parts.append(f"{color}{text}{reset}")

print(" | ".join(parts))
PY
}

render_stories() {
    printf '%bTop Stories%b\n' "$DASH_CYAN" "$DASH_RESET"
    printf '%b-----------%b\n' "$DASH_MUTED" "$DASH_RESET"
    local news_json
    news_json="$(read_news_cache_json)"

    NEWS_JSON="$news_json" TITLE_COLOR="$DASH_CYAN" META_COLOR="$DASH_MAGENTA" SUMMARY_COLOR="$DASH_FG" RESET_COLOR="$DASH_RESET" python3 - <<'PY'
import json
import os
import shutil
import textwrap

TITLE = os.environ.get("TITLE_COLOR", "")
META = os.environ.get("META_COLOR", "")
SUMMARY = os.environ.get("SUMMARY_COLOR", "")
RESET = os.environ.get("RESET_COLOR", "")

term_size = shutil.get_terminal_size((96, 40))
pane_width = max(term_size.columns, 40)
pane_height = max(term_size.lines, 8)

usable_lines = max(pane_height - 4, 3)

def wrap_block(text, initial_indent, subsequent_indent):
    width = max(pane_width - len(initial_indent), 20)
    return textwrap.wrap(
        text,
        width=width,
        initial_indent=initial_indent,
        subsequent_indent=subsequent_indent,
        break_long_words=False,
        break_on_hyphens=False,
    ) or [initial_indent.rstrip()]

data = json.loads(os.environ.get("NEWS_JSON", "{}"))
stories = data.get("stories", [])

if not stories:
    print("No stories available right now.")
else:
    used_lines = 0
    last_source = None
    for idx, story in enumerate(stories[:9], start=1):
        source = story.get("source", "Feed")
        title = story.get("title", "")
        summary = story.get("summary", "No summary available.")
        title_lines = textwrap.wrap(
            f"[{idx}] {title}",
            width=max(pane_width, 24),
            initial_indent="",
            subsequent_indent="    ",
            break_long_words=False,
            break_on_hyphens=False,
            max_lines=2,
            placeholder="...",
        ) or [f"[{idx}] {title}"]
        source_lines = 1 if source != last_source else 0
        summary_budget = max(min(3, usable_lines - used_lines - len(title_lines) - source_lines - 1), 1)
        summary_lines = textwrap.wrap(
            summary,
            width=max(pane_width - 2, 24),
            initial_indent="  ",
            subsequent_indent="  ",
            break_long_words=False,
            break_on_hyphens=False,
            max_lines=summary_budget,
            placeholder="...",
        ) or ["    No summary available."]

        story_lines = source_lines + len(title_lines) + len(summary_lines) + 1
        if used_lines + story_lines > usable_lines:
            if used_lines == 0:
                if source_lines:
                    print(f"{META}{source}{RESET}")
                print(f"{TITLE}{title_lines[0]}{RESET}")
                print(f"{SUMMARY}{summary_lines[0]}{RESET}")
            break

        if source_lines:
            print(f"{META}{source}{RESET}")
            last_source = source
        for line in title_lines:
            print(f"{TITLE}{line}{RESET}")
        for line in summary_lines:
            print(f"{SUMMARY}{line}{RESET}")
        print()
        used_lines += story_lines
PY
    printf 'Updated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}

render_repo() {
    render_header "Repo Status"

    local json_output=""
    if [[ -x "$REPOSTATUS_PATH" ]]; then
        json_output="$(REPOSTATUS_DISABLE_FETCH=1 "$REPOSTATUS_PATH" --json-summary 2>/dev/null || true)"
    elif command -v repostatus >/dev/null 2>&1; then
        json_output="$(REPOSTATUS_DISABLE_FETCH=1 repostatus --json-summary 2>/dev/null || true)"
    fi

    if [[ -z "$json_output" ]]; then
        printf 'repostatus summary unavailable.\n'
        return
    fi

    REPOSTATUS_JSON="$json_output" INFO_COLOR="$DASH_CYAN" OK_COLOR="$DASH_GREEN" WARN_COLOR="$DASH_YELLOW" ERR_COLOR="$DASH_RED" META_COLOR="$DASH_MUTED" RESET_COLOR="$DASH_RESET" python3 - <<'PY'
import json
import os
import shutil

INFO = os.environ.get("INFO_COLOR", "")
OK = os.environ.get("OK_COLOR", "")
WARN = os.environ.get("WARN_COLOR", "")
ERR = os.environ.get("ERR_COLOR", "")
META = os.environ.get("META_COLOR", "")
RESET = os.environ.get("RESET_COLOR", "")
pane_height = max(shutil.get_terminal_size((80, 24)).lines, 8)
usable_lines = max(pane_height - 5, 3)

def status_color(status):
    return {
        "clean": OK,
        "ahead": INFO,
        "behind": WARN,
        "dirty": WARN,
        "diverged": ERR,
        "fetch_failed": ERR,
        "uninitialized": META,
    }.get(status, RESET)

try:
    data = json.loads(os.environ.get("REPOSTATUS_JSON", ""))
except Exception:
    print("Unable to parse repostatus summary.")
    raise SystemExit(0)

remaining = max(usable_lines, 1)
repos = [repo for repo in data.get("repos", []) if repo.get("status") != "clean"]
if not repos:
    repos = data.get("repos", [])

if not repos:
    print("All tracked repos are clean.")
else:
    for repo in repos:
        if remaining <= 0:
            break
        path = repo.get("path", "")
        short_path = path.replace("/home/groot/", "~/") if path else ""
        status = repo.get("status", "unknown")
        color = status_color(status)
        print(f"{color}- {status:<9} {repo.get('name', 'repo')}{RESET}")
        remaining -= 1
        if remaining <= 0:
            break
        if short_path:
            print(f"  {META}{short_path}{RESET}")
            remaining -= 1

    extra = len(repos)
    shown = 0
    remaining = max(usable_lines, 1)
    for repo in repos:
        lines = 1 + (1 if repo.get("path", "") else 0)
        if remaining - lines < 0:
            break
        remaining -= lines
        shown += 1
    hidden = max(extra - shown, 0)
    if hidden and remaining > 0:
        print(f"{META}... and {hidden} more{RESET}")
PY
}

render_utility() {
    render_header "Package Updates"
    if command -v yay >/dev/null 2>&1; then
        local updates
        updates="$(yay -Qu 2>/dev/null || true)"
        if [[ -n "$updates" ]]; then
            printf '%bCount:%b %s\n' "$DASH_CYAN" "$DASH_RESET" "$(printf '%s\n' "$updates" | wc -l)"
            UPDATE_LINES="$updates" PKG_COLOR="$DASH_ORANGE" RESET_COLOR="$DASH_RESET" python3 - <<'PY'
import os
import shutil

PKG = os.environ.get("PKG_COLOR", "")
RESET = os.environ.get("RESET_COLOR", "")
pane_height = max(shutil.get_terminal_size((80, 24)).lines, 8)
usable_lines = max(pane_height - 4, 2)

lines = [line.rstrip() for line in os.environ.get("UPDATE_LINES", "").splitlines() if line.strip()]
shown = max(usable_lines - 1, 1)
for line in lines[:shown]:
    print(f"{PKG}- {line}{RESET}")
if len(lines) > shown and usable_lines > shown:
    print(f"{PKG}- ... and {len(lines) - shown} more{RESET}")
PY
        else
            printf '%bNo updates available.%b\n' "$DASH_GREEN" "$DASH_RESET"
        fi
    else
        printf '%byay is not installed.%b\n' "$DASH_RED" "$DASH_RESET"
    fi
}

render_sports_compact() {
    TITLE_COLOR="$DASH_ORANGE" META_COLOR="$DASH_MAGENTA" RESET_COLOR="$DASH_RESET" python3 - <<'PY'
import json
import os
import urllib.request

TITLE = os.environ.get("TITLE_COLOR", "")
META = os.environ.get("META_COLOR", "")
RESET = os.environ.get("RESET_COLOR", "")

feeds = [
    ("NFL", "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"),
    ("NHL", "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard"),
    ("NBA", "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"),
]

items = []
for league, url in feeds:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "tmux-dashboard/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.load(resp)
    except Exception:
        continue

    for event in data.get("events", [])[:6]:
        competitors = []
        for comp in event.get("competitions", [])[:1]:
            for competitor in comp.get("competitors", []):
                team = competitor.get("team", {}).get("abbreviation", "TEAM")
                score = competitor.get("score", "0")
                competitors.append(f"{team} {score}")
        status = event.get("status", {}).get("type", {}).get("shortDetail", "Status unavailable")
        matchup = " vs ".join(competitors) if competitors else event.get("shortName", "Game")
        items.append(f"{league} {matchup} {status}")

if not items:
    print("No scores available.")
else:
    print(" | ".join(items))
PY
}

render_sports() {
    render_header "Sports Scoreboard"
    TITLE_COLOR="$DASH_ORANGE" META_COLOR="$DASH_MAGENTA" RESET_COLOR="$DASH_RESET" python3 - <<'PY'
import json
import os
import shutil
import urllib.request

TITLE = os.environ.get("TITLE_COLOR", "")
META = os.environ.get("META_COLOR", "")
RESET = os.environ.get("RESET_COLOR", "")
pane_height = max(shutil.get_terminal_size((80, 24)).lines, 10)
usable_lines = max(pane_height - 5, 4)

feeds = [
    ("NFL", "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"),
    ("NHL", "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard"),
    ("NBA", "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"),
]

found_any = False
used_lines = 0
for league, url in feeds:
    if used_lines >= usable_lines:
        break
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "tmux-dashboard/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.load(resp)
    except Exception:
        if used_lines + 3 > usable_lines:
            break
        print(f"{TITLE}{league}{RESET}")
        print(f"  {META}feed unavailable{RESET}")
        print()
        used_lines += 3
        continue

    events = data.get("events", [])[:6]
    if used_lines + 2 > usable_lines:
        break
    print(f"{TITLE}{league}{RESET}")
    print(f"{META}{'-' * len(league)}{RESET}")
    used_lines += 2
    if not events:
        if used_lines + 2 > usable_lines:
            break
        print(f"{META}No games found.{RESET}")
        print()
        used_lines += 2
        continue

    found_any = True
    for event in events:
        if used_lines + 2 > usable_lines:
            break
        status = event.get("status", {}).get("type", {}).get("shortDetail", "Status unavailable")
        lines = []
        for comp in event.get("competitions", [])[:1]:
            for competitor in comp.get("competitors", []):
                team = competitor.get("team", {}).get("abbreviation", "TEAM")
                score = competitor.get("score", "0")
                lines.append(f"{team} {score}")
        matchup = " | ".join(lines) if lines else event.get("shortName", "Game")
        print(f"{TITLE}{matchup}{RESET}")
        print(f"  {META}{status}{RESET}")
        used_lines += 2
    if used_lines < usable_lines:
        print()
        used_lines += 1

if not found_any:
    print(f"{META}No sports data available.{RESET}")
PY
    printf 'Updated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}

render_sports_home() {
    render_header "Sports Board"
    TITLE_COLOR="$DASH_ORANGE" META_COLOR="$DASH_MAGENTA" RESET_COLOR="$DASH_RESET" python3 - <<'PY'
import json
import os
import shutil
import urllib.request

TITLE = os.environ.get("TITLE_COLOR", "")
META = os.environ.get("META_COLOR", "")
RESET = os.environ.get("RESET_COLOR", "")
pane_height = max(shutil.get_terminal_size((80, 24)).lines, 8)
usable_lines = max(pane_height - 5, 3)

def colorize(kind, text):
    if not text:
        return ""
    if kind == "title":
        return f"{TITLE}{text}{RESET}"
    if kind == "meta":
        return f"{META}{text}{RESET}"
    return text

feeds = [
    ("NFL", "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"),
    ("NHL", "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard"),
    ("NBA", "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"),
]

blocks = []
for league, url in feeds:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "tmux-dashboard/1.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.load(resp)
    except Exception:
        blocks.append([("title", league), ("meta", "-" * len(league)), ("meta", "feed unavailable")])
        continue

    events = data.get("events", [])[:3]
    if not events:
        blocks.append([("title", league), ("meta", "-" * len(league)), ("meta", "no games")])
        continue

    lines = [("title", league), ("meta", "-" * len(league))]
    for event in events:
        status = event.get("status", {}).get("type", {}).get("shortDetail", "Status unavailable")
        teams = []
        for comp in event.get("competitions", [])[:1]:
            for competitor in comp.get("competitors", []):
                team = competitor.get("team", {}).get("abbreviation", "TEAM")
                score = competitor.get("score", "0")
                teams.append(f"{team} {score}")
        lines.append(("title", ' | '.join(teams) if teams else event.get('shortName', 'Game')))
        lines.append(("meta", f"  {status}"))
    blocks.append(lines)

col_width = 28
max_rows = max(len(block) for block in blocks) if blocks else 0
for row in range(min(max_rows, usable_lines)):
    values = []
    for block in blocks:
        values.append(block[row] if row < len(block) else ("plain", ""))

    left_kind, left_text = values[0]
    mid_kind, mid_text = values[1]
    right_kind, right_text = values[2]

    left_cell = colorize(left_kind, f"{left_text:<{col_width}}")
    mid_cell = colorize(mid_kind, f"{mid_text:<{col_width}}")
    right_cell = colorize(right_kind, right_text)
    print(f"{left_cell}  {mid_cell}  {right_cell}")
PY
    printf 'Updated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}

render_help() {
    render_header "Dashboard Keys"
    cat <<'EOF'
- Prefix          Ctrl-b
- Prefix + w      choose window from a list
- Prefix + 0-5    jump directly to a window
- Prefix + n/p    next or previous window
- Prefix + arrows move between panes
- Prefix + z      zoom the active pane
- Hyprland Super+B      dashboard load/reload/surface menu
- Hyprland Super+N      open story picker
- Hyprland Super+Shift+R repo actions
- Window 0        home
- Window 1        monitor
- Window 2        feeds
- Window 3        git
- Window 4        sports
- Window 5        help
EOF
}

pane_loop() {
    local interval="$1"
    local renderer="$2"

    while true; do
        clear
        "$renderer"
        sleep "$interval"
    done
}

run_pane() {
    local pane_name="${1:-}"
    case "$pane_name" in
        ticker)
            run_ticker_loop
            ;;
        stories)
            pane_loop 300 render_stories
            ;;
        repo)
            pane_loop 120 render_repo
            ;;
        utility)
            pane_loop 300 render_utility
            ;;
        sports-home)
            pane_loop 60 render_sports_home
            ;;
        sports)
            pane_loop 60 render_sports
            ;;
        help)
            pane_loop 600 render_help
            ;;
        monitor)
            run_or_fallback_monitor
            ;;
        monitor-compact)
            run_or_fallback_monitor_compact
            ;;
        feeds)
            run_or_fallback_newsboat
            ;;
        git)
            run_or_fallback_repostatus
            ;;
        *)
            die "Unknown pane: $pane_name"
            ;;
    esac
}

render_once() {
    local pane_name="${1:-}"
    case "$pane_name" in
        ticker)
            render_ticker
            ;;
        stories) render_stories ;;
        repo) render_repo ;;
        utility) render_utility ;;
        sports-home) render_sports_home ;;
        sports) render_sports ;;
        help) render_help ;;
        *) die "Unknown render target: $pane_name" ;;
    esac
}

setup_dashboard_keybindings() {
    tmux unbind-key O >/dev/null 2>&1 || true
    tmux unbind-key R >/dev/null 2>&1 || true
}

create_home_window() {
    local window_ref="$SESSION_NAME:home"
    local root_pane top_pane right_pane stories_pane monitor_pane sports_pane lower_right_pane
    local utility_pane repo_pane window_width story_width
    local session_width session_height

    session_width="$(tput cols 2>/dev/null || printf '160')"
    session_height="$(tput lines 2>/dev/null || printf '48')"

    tmux new-session -d -x "$session_width" -y "$session_height" -s "$SESSION_NAME" -n home

    root_pane="$(tmux display-message -p -t "$window_ref.0" '#{pane_id}')"
    window_width="$(tmux display-message -p -t "$window_ref" '#{window_width}')"

    story_width=96
    if (( window_width < 140 )); then
        story_width=$((window_width * 62 / 100))
    fi
    if (( story_width < 60 )); then
        story_width=60
    fi
    if (( story_width > window_width - 40 )); then
        story_width=$((window_width - 40))
    fi

    top_pane="$(tmux split-window -dPF '#{pane_id}' -t "$root_pane" -v -b -l 7)"
    stories_pane="$(tmux split-window -dPF '#{pane_id}' -t "$root_pane" -h -b -l "$story_width")"
    right_pane="$root_pane"
    monitor_pane="$(tmux split-window -dPF '#{pane_id}' -t "$right_pane" -v -b -l 12)"
    lower_right_pane="$right_pane"
    sports_pane="$(tmux split-window -dPF '#{pane_id}' -t "$lower_right_pane" -v -b -l 18)"
    repo_pane="$lower_right_pane"
    utility_pane="$(tmux split-window -dPF '#{pane_id}' -t "$lower_right_pane" -h -b -p 50)"

    tmux respawn-pane -k -t "$top_pane" "$(tmux_pane_command ticker)"
    tmux respawn-pane -k -t "$stories_pane" "$(tmux_pane_command stories)"
    tmux respawn-pane -k -t "$monitor_pane" "$(tmux_pane_command monitor-compact)"
    tmux respawn-pane -k -t "$sports_pane" "$(tmux_pane_command sports-home)"
    tmux respawn-pane -k -t "$utility_pane" "$(tmux_pane_command utility)"
    tmux respawn-pane -k -t "$repo_pane" "$(tmux_pane_command repo)"

    tmux select-pane -t "$stories_pane"
}

create_extra_windows() {
    tmux new-window -t "$SESSION_NAME" -n monitor "$(tmux_pane_command monitor)"
    tmux new-window -t "$SESSION_NAME" -n feeds "$(tmux_pane_command feeds)"
    tmux new-window -t "$SESSION_NAME" -n git "$(tmux_pane_command git)"
    tmux new-window -t "$SESSION_NAME" -n sports "$(tmux_pane_command sports)"
    tmux new-window -t "$SESSION_NAME" -n help "$(tmux_pane_command help)"
    tmux select-window -t "$SESSION_NAME:home"
}

launch_dashboard() {
    require_commands tmux python3
    setup_dashboard_keybindings

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        if [[ "${1:-attach}" = "attach" ]]; then
            attach_dashboard
        fi
        return
    fi

    create_home_window
    create_extra_windows
    if [[ "${1:-attach}" = "attach" ]]; then
        attach_dashboard
    fi
}

main() {
    case "${1:-launch}" in
        launch)
            launch_dashboard attach
            ;;
        launch-detached)
            launch_dashboard detached
            ;;
        open-story)
            shift
            open_story "${1:-}"
            ;;
        menu)
            shift
            case "${1:-}" in
                stories) story_menu ;;
                repos) repo_menu ;;
                *) die "Unknown menu: ${1:-}" ;;
            esac
            ;;
        pane)
            shift
            run_pane "${1:-}"
            ;;
        render)
            shift
            render_once "${1:-}"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            die "Unknown command: $1"
            ;;
    esac
}

main "$@"
