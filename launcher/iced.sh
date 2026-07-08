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
# Script: iced.sh
# Purpose: Freeze/thaw browser tabs to a hand-editable Markdown DB; reclaim 100% browser RAM
# Dependencies: fuzzel, wl-paste, pgrep, ps, mktemp, hyprctl, jq, awk
#               optional: notify-send (keybind feedback), wl-copy (race-free grabs)
#               qutebrowser: socat
#               firefox:     ydotool (optional; falls back to clipboard)
#               chromium/brave: curl (CDP JSON API; requires --remote-debugging-port)
# Author: groot
# Modified: 2026-07-08

set -euo pipefail

source "/home/groot/projects/scripts/lib/colors.sh"
source "/home/groot/projects/scripts/lib/common.sh"

# ─── Keybind-Visible Feedback ────────────────────────────────────────────────
#
# This script is normally invoked from a Hyprland keybind: stdout/stderr go
# nowhere, so print_*/die alone produce *silent* failures (the "keybind did
# nothing" experience).  Every user-visible outcome must also raise a desktop
# notification.  notify-send is optional; absence degrades to terminal-only.

# _notify <urgency> <title> <body>
_notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send --app-name=iced --urgency="$1" "$2" "$3" 2>/dev/null || true
}

# Shadow common.sh's die so every fatal path notifies before exiting; must be
# defined *after* sourcing common.sh so this definition wins.
die() {
    local msg="${1:-Unknown error}"
    local code="${2:-1}"
    _notify critical "iced: failed" "$msg"
    print_error "$msg"
    exit "$code"
}

# ─── Static Configuration ────────────────────────────────────────────────────

# Markdown database, human-editable for bulk management.  Lives inside the
# journal repo so it is git-backed alongside the other notes and reachable
# from the journal dashboard (journal.sh tabs / surface-tabs).
# Override the location with ICED_DB, or the journal root with JOURNAL_DIR.
#
#   ## category                       ← one section per category
#   - https://url <!--browser-->      ← one bullet per frozen tab
#
# Parsing rules (everything else — titles, prose, blanks — is ignored):
#   - `## name` starts a category; bullets before any heading → DEFAULT_CATEGORY
#   - `- url` or `* url`; a `[title](url)` markdown link also works
#   - the trailing `<!--browser-->` comment records the origin browser so thaw
#     can reopen there; hand-added bullets without it open via xdg-open
#   - FILE ORDER IS AUTHORITATIVE: rearranging sections/bullets in an editor
#     rearranges the fuzzel menus; new freezes insert at the top of their section
readonly JOURNAL_DIR="${JOURNAL_DIR:-$HOME/projects/journal}"
readonly TAB_DB="${ICED_DB:-${JOURNAL_DIR}/notes/tabs.md}"

# journal.sh integration: `edit` surfaces the journal-managed tabs window so
# the picker row, the CLI, and the journal keybinds all share ONE window
readonly ICED_JOURNAL="${ICED_JOURNAL:-$HOME/.local/bin/journal.sh}"

# Bucket for entries frozen without an explicit category
readonly DEFAULT_CATEGORY="unsorted"

# Pinned menu row that opens the DB in an editor (persistent in every picker)
readonly EDIT_ROW="✎ edit tab list"

# qutebrowser IPC sockets live under $XDG_RUNTIME_DIR/qutebrowser/
readonly QUTE_IPC_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/qutebrowser"

# Max seconds to wait for qutebrowser IPC before declaring failure
readonly QUTE_IPC_TIMEOUT=2

# Chromium DevTools Protocol port; only active if browser launched with
# --remote-debugging-port=N.  Override via env: ICED_CDP_PORT=9223
readonly CDP_PORT="${ICED_CDP_PORT:-9222}"

# Override auto-detection by setting ICED_BROWSER=firefox|chromium|brave|qutebrowser
# If unset the active Hyprland window class is interrogated at runtime.
readonly FORCED_BROWSER="${ICED_BROWSER:-}"

# ─── Browser Registry ────────────────────────────────────────────────────────
#
# Each browser is identified by three attributes encoded in parallel arrays
# (bash 3 compat; associative arrays require bash 4+ and are fine here but
# parallel arrays keep the registry readable as a table):
#
#   BROWSER_KEYS  – canonical name used as dispatch key
#   BROWSER_PROCS – exact /proc/<pid>/comm string for pgrep -x
#   BROWSER_GRAB  – name of the URL-grab function to call (primary path)
#
# Hyprland window class → canonical name mapping lives in _detect_browser().

BROWSER_KEYS=( qutebrowser firefox chromium brave )
# Space-separated alternatives: canonical key may map to several comm names
# (firefox-esr/librewolf detect as "firefox" but run under their own comm)
BROWSER_PROCS=( "qutebrowser" "firefox firefox-esr firefox-bin librewolf" "chromium chromium-browser chrome" "brave brave-browser" )
BROWSER_GRAB=( _grab_qutebrowser _grab_urlbar _grab_chromium _grab_chromium )

# ─── Browser Detection ───────────────────────────────────────────────────────

# Resolve which browser is "active" using a priority chain:
#   1. $ICED_BROWSER env var (explicit user override)
#   2. hyprctl activewindow class (active Wayland surface)
#   3. First browser process found running via pgrep
#   4. "clipboard" sentinel → raw wl-paste with no process kill
_detect_browser() {
    [[ -n "$FORCED_BROWSER" ]] && { echo "$FORCED_BROWSER"; return; }

    # hyprctl -j exposes the active surface's wm_class which is the most
    # reliable signal when multiple browsers are installed concurrently
    local wclass=""
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        wclass=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty') || true
    fi

    # Normalise to lowercase; match Wayland app_ids which are often reverse-DNS
    # (org.qutebrowser.qutebrowser, org.mozilla.firefox, org.chromium.Chromium).
    # Patterns are ANCHORED on purpose: bare substring globs like *chrome*
    # match Electron apps and PWA wrappers (class "chrome-<appid>-Default",
    # "code", "discord", …) and send ice down the CDP path against a window
    # that is not a browser — then kill_browser SIGTERMs innocent processes.
    case "${wclass,,}" in
        qutebrowser|org.qutebrowser.*)                     echo "qutebrowser"; return ;;
        firefox*|librewolf*|org.mozilla.*)                 echo "firefox";     return ;;
        chromium|chromium-browser|org.chromium.*|\
        google-chrome|google-chrome-*|chrome)              echo "chromium";    return ;;
        brave|brave-browser|brave-browser-*|com.brave.*)   echo "brave";       return ;;
    esac

    # Active window class didn't match → fall back to first running browser.
    # ONE ps snapshot + pure-bash substring matching instead of a pgrep fork
    # per (browser × comm-name) — the old probe spawned up to ~10 processes.
    log_warn "Could not detect browser from window class '${wclass}'; probing running processes"
    local procs="" i name
    procs=$'\n'$(ps -eo comm= 2>/dev/null)$'\n'
    for i in "${!BROWSER_KEYS[@]}"; do
        for name in ${BROWSER_PROCS[$i]}; do   # word-split intentional
            if [[ "$procs" == *$'\n'"$name"$'\n'* ]]; then
                echo "${BROWSER_KEYS[$i]}"; return
            fi
        done
    done

    # Nothing found; we can still save from clipboard (user manually copies URL)
    echo "clipboard"
}

# ─── URL Grabbers (per-browser) ───────────────────────────────────────────────

# The grab functions write the URL to the Wayland clipboard as a side-effect
# and we read it back.  A fixed sleep is racy: too short and wl-paste returns
# the *previous* clipboard content — which may itself be an https URL from an
# earlier ice, so it validates and the WRONG tab gets frozen (and the browser
# killed).  Instead: clear the clipboard first, then poll until fresh content
# appears.  Clearing also guarantees the raw-clipboard fallback can never
# resurrect stale pre-grab content after a failed injection.

# Best-effort clipboard clear; wl-copy ships with wl-clipboard alongside wl-paste
_clipboard_clear() {
    command -v wl-copy >/dev/null 2>&1 || return 0
    wl-copy --clear 2>/dev/null || true
}

# Poll the clipboard until non-empty (max ~1.6s); echoes content on success
_clipboard_poll() {
    local content="" tries
    for tries in {1..8}; do
        sleep 0.2
        content=$(wl-paste --no-newline 2>/dev/null) || true
        if [[ -n "$content" ]]; then
            printf '%s' "$content"
            return 0
        fi
    done
    return 1
}

# qutebrowser: send :yank via the UNIX IPC socket; qutebrowser writes the
# active tab URL to the Wayland clipboard as a side-effect.  Protocol is
# newline-delimited JSON; protocol_version=1 is stable across all post-1.0
# releases.  socat bridges our stdout into the socket's stdin.
_grab_qutebrowser() {
    local socket=""
    socket=$(find "$QUTE_IPC_DIR" -maxdepth 1 -name "ipc-*" -type s 2>/dev/null \
        | head -1) || true

    if [[ -z "$socket" || ! -S "$socket" ]]; then
        log_warn "qutebrowser IPC socket not found under ${QUTE_IPC_DIR}"
        return 1
    fi

    local payload
    printf -v payload \
        '{"args":[":yank"],"target_arg":null,"version":"1.0.0","protocol_version":1,"cwd":"%s"}' \
        "$PWD"

    _clipboard_clear

    # timeout guards against hung qutebrowser; discard ack JSON from socket
    if printf '%s\n' "$payload" \
        | timeout "$QUTE_IPC_TIMEOUT" socat - "UNIX-CONNECT:${socket}" \
        >/dev/null 2>&1; then
        # IPC dispatch is async; poll for the clipboard flush instead of a
        # single fixed sleep (slow event loop ticks caused stale grabs)
        _clipboard_poll && return 0
    fi

    log_warn "qutebrowser IPC timed out, socat failed, or clipboard never updated"
    return 1
}

# Firefox (and any browser with a Ctrl+L address bar): no native IPC on
# Wayland.  Use ydotool to simulate Ctrl+L (focus address bar) → Ctrl+A
# (select all) → Ctrl+C (copy to clipboard).  ydotool requires membership in
# the 'input' group or CAP_SYS_RAWIO; fails gracefully to clipboard fallback
# if unavailable or unprivileged.
_grab_urlbar() {
    if ! command -v ydotool >/dev/null 2>&1; then
        log_warn "ydotool not found; cannot automate URL-bar capture"
        return 1
    fi

    # This runs from a Hyprland keybind (Super+Shift+I): the user's modifiers
    # are still PHYSICALLY HELD when we inject, so the browser would receive
    # Ctrl+Super+Shift+L — not "focus address bar".  Inject key-UP events for
    # every bind modifier first; releasing an unpressed key is a no-op.
    # key codes: 125/126=meta(l/r) 42/54=shift(l/r) 56/100=alt(l/r)
    ydotool key 125:0 126:0 42:0 54:0 56:0 100:0 2>/dev/null || true
    sleep 0.1

    _clipboard_clear

    # ydotool ≥1.0 'key' takes evdev KEYCODE:STATE pairs (1=press 0=release);
    # symbolic names like 'ctrl+l' and --clearmodifiers are xdotool-isms.
    # key codes: 29=ctrl 38=l 30=a 46=c
    if ! ydotool key 29:1 38:1 38:0 29:0 2>/dev/null; then   # Ctrl+L
        log_warn "ydotool key injection failed (is ydotoold running? check 'input' group)"
        return 1
    fi
    sleep 0.15   # address bar focus is async; wait for UI update
    ydotool key 29:1 30:1 30:0 29:0 2>/dev/null || true      # Ctrl+A
    ydotool key 29:1 46:1 46:0 29:0 2>/dev/null || true      # Ctrl+C

    # clipboard write is async; poll until the copy lands (max ~1.6s)
    _clipboard_poll
}

# Chromium / Brave: Chrome DevTools Protocol (CDP) exposes a /json endpoint
# listing all open tabs with their URLs.  Requires the browser to have been
# launched with --remote-debugging-port=${CDP_PORT}.  We pick the first
# active/focused tab (type=page, not devtools/extension panels).
# curl -sf fails silently if port isn't open → caller falls back to clipboard.
_grab_cdp() {
    local tab_url=""
    tab_url=$(curl -sf --max-time 2 "http://127.0.0.1:${CDP_PORT}/json" 2>/dev/null \
        | jq -r '[.[] | select(.type=="page")] | first | .url // empty') || true

    if [[ -z "$tab_url" ]]; then
        log_warn "CDP endpoint at port ${CDP_PORT} unreachable or returned no pages"
        return 1
    fi

    echo "$tab_url"
}

# Chromium/Brave: prefer CDP (exact, no focus dependency) but chain to the
# generic Ctrl+L urlbar copy when the browser wasn't launched with
# --remote-debugging-port — the common case, and previously a guaranteed
# fall-through to the unsafe raw-clipboard path.
_grab_chromium() {
    _grab_cdp && return 0
    log_warn "CDP grab failed; trying ydotool URL-bar copy"
    _grab_urlbar
}

# ─── Unified URL Resolution ───────────────────────────────────────────────────

# Orchestrates the two-stage (primary + clipboard fallback) URL resolution
# for the given browser (detected once by the caller and passed as $1 to
# avoid re-detection races).  Sets globals instead of echoing so the caller
# also learns HOW the URL was obtained — command substitution would run us
# in a subshell and discard that flag:
#   GRAB_URL    – the resolved URL
#   GRAB_SOURCE – "primary"  (browser-verified: safe to kill the browser)
#                 "clipboard" (unverified: may be stale; do NOT kill on it)
GRAB_URL=""
GRAB_SOURCE=""

resolve_url() {
    local browser="$1" url=""
    log_debug "Detected browser: ${browser}"

    if [[ "$browser" != "clipboard" ]]; then
        # Walk the registry to find the matching grab function
        local i
        for i in "${!BROWSER_KEYS[@]}"; do
            if [[ "${BROWSER_KEYS[$i]}" == "$browser" ]]; then
                url=$("${BROWSER_GRAB[$i]}" 2>/dev/null) || true
                break
            fi
        done
    fi

    # Validate the primary result is an HTTP/S URI; anything else (file://,
    # clipboard noise, empty string) routes to the clipboard fallback path
    if [[ "$url" =~ ^https?:// ]]; then
        GRAB_URL="$url"
        GRAB_SOURCE="primary"
        return 0
    fi

    log_warn "Primary grab failed or returned non-URL; falling back to raw clipboard"
    url=$(wl-paste --no-newline 2>/dev/null) || true

    [[ -n "$url" ]] || die "No URL found via primary grab or clipboard" 1
    GRAB_URL="$url"
    GRAB_SOURCE="clipboard"
}

# ─── Process Termination ─────────────────────────────────────────────────────

# Resolve PIDs by exact comm match (pgrep -x) to avoid name-prefix collisions
# (e.g., 'chromium' vs 'chromium-sandbox').  Sends SIGTERM so the browser can
# flush sessions, close sockets, and unlink lock files cleanly.
kill_browser() {
    local browser="$1" proc_names=""

    local i
    for i in "${!BROWSER_KEYS[@]}"; do
        if [[ "${BROWSER_KEYS[$i]}" == "$browser" ]]; then
            proc_names="${BROWSER_PROCS[$i]}"
            break
        fi
    done

    [[ -n "$proc_names" ]] || { log_warn "No proc name for browser '${browser}'"; return 0; }

    # Single pgrep call: -x takes an ERE, so all comm-name alternatives
    # collapse into one alternation instead of a fork per name
    local -a pids=()
    mapfile -t pids < <(pgrep -x "${proc_names// /|}" 2>/dev/null) || true

    if (( ${#pids[@]} == 0 )); then
        log_warn "No running process for '${browser}' (tried: ${proc_names}); tab saved, nothing killed"
        print_warn "Browser not running; tab saved only"
        return 0
    fi

    kill -TERM "${pids[@]}"
    log_info "SIGTERM → ${browser} PID(s): ${pids[*]}"
    print_success "Browser terminated (PID ${pids[*]}); RAM fully reclaimed"
}

# ─── DB Helpers ──────────────────────────────────────────────────────────────

# Shared awk functions for the Markdown schema; every DB-touching awk program
# is prefixed with this library so heading/bullet parsing stays identical
# between the reader, the deduper, and the rewriters.
readonly AWK_MD_LIB='
    # "## name" → "name" (surrounding whitespace trimmed)
    function md_heading(line) {
        sub(/^##[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        return line
    }
    # bullet line → bare URL ("" when the bullet is empty)
    function md_url(line) {
        sub(/^[-*][[:space:]]+/, "", line)
        sub(/[[:space:]]*<!--.*$/, "", line)              # strip browser comment
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line ~ /^\[[^\]]*\]\([^)]+\)/) {              # [title](url) form
            sub(/^\[[^\]]*\]\(/, "", line)
            sub(/\).*$/, "", line)
        } else if (match(line, /[[:space:]]/)) {          # first token only
            line = substr(line, 1, RSTART - 1)
        }
        return line
    }
    # bullet line → browser from a trailing <!--browser--> ("" when absent)
    function md_browser(line,   b) {
        if (match(line, /<!--[^>]*-->[[:space:]]*$/)) {
            b = substr(line, RSTART, RLENGTH)
            sub(/^<!--[[:space:]]*/, "", b)
            sub(/[[:space:]]*-->[[:space:]]*$/, "", b)
            return b
        }
        return ""
    }
'

# Parse the Markdown DB into a canonical URL<TAB>browser<TAB>category stream —
# the single source of truth every consumer (menus, lookups, counts) builds on.
_db_entries() {
    [[ -f "$TAB_DB" ]] || return 0
    awk -v def="$DEFAULT_CATEGORY" "$AWK_MD_LIB"'
        /^##[[:space:]]/ { cat = md_heading($0); next }
        /^[-*][[:space:]]/ {
            u = md_url($0)
            if (u == "") next
            printf "%s\t%s\t%s\n", u, md_browser($0), (cat == "" ? def : cat)
        }' "$TAB_DB"
}

# Self-documenting skeleton so a hand-editor always knows the rules
_write_skeleton() {
    cat > "$TAB_DB" <<'EOF'
# ❄ iced tabs

Frozen browser tabs. One `- URL` bullet per tab, grouped under `## category`
headings. Edit freely for bulk management: move bullets between sections,
delete lines, add new URLs, reorder anything — menu order follows file order.
The trailing `<!--browser-->` comment records where a tab reopens; bullets
without one open in the default browser.
EOF
}

init_db() {
    ensure_dir "$(dirname "$TAB_DB")"
    [[ -f "$TAB_DB" ]] || _write_skeleton
}

# Atomically rewrite the DB through a filter:  <env> _db_rewrite <awk-program>
# The program is automatically prefixed with AWK_MD_LIB.  Match values travel
# via exported env vars (ENVIRON[]) so arbitrary URL bytes survive — awk -v
# would mangle backslashes.
#   - mktemp lands in the same directory → same filesystem → mv is a single
#     rename(2) syscall; concurrent readers never see a torn state
#   - awk failure ABORTS and keeps the DB untouched (an earlier `|| true`
#     variant let mv replace the whole DB with an empty temp file)
_db_rewrite() {
    local prog="$1" tmp_db
    tmp_db=$(mktemp "${TAB_DB}.XXXXXX")
    if ! awk "${AWK_MD_LIB}${prog}" "$TAB_DB" > "$tmp_db"; then
        rm -f "$tmp_db"
        die "DB rewrite failed; database left untouched" 1
    fi
    mv -f "$tmp_db" "$TAB_DB"
}

# ─── Category & Menu Helpers ─────────────────────────────────────────────────

# Unique categories in file order.  Reads HEADINGS (not entries) so empty
# sections pre-created by hand are still offered as freeze targets.
_existing_categories() {
    [[ -f "$TAB_DB" ]] || return 0
    awk "$AWK_MD_LIB"'
        /^##[[:space:]]/ {
            h = md_heading($0)
            if (h != "" && !(h in seen)) { seen[h] = 1; print h }
        }' "$TAB_DB"
}

# Render the DB as a fuzzel menu grouped under category sub-headings:
#   ── work ──
#     https://…
#   ✎ edit tab list
# Sections and entries appear in FILE order (manual edits control the layout).
# Headings are unindented `── name ──`; tabs are indented two spaces so the
# row types can never collide when parsing the selection.  The pinned edit row
# is always last.
_grouped_menu() {
    _db_entries | awk -F'\t' '
        {
            if (!($3 in seen)) { seen[$3] = 1; order[++n] = $3 }
            items[$3] = items[$3] "  " $1 "\n"
        }
        END {
            for (i = 1; i <= n; i++) {
                printf "── %s ──\n%s", order[i], items[order[i]]
            }
        }'
    printf '%s\n' "$EDIT_ROW"
}

# Present the grouped menu and classify the selection.  Sets:
#   PICK_TYPE  – "url" | "category" | "edit" | "none"
#   PICK_VALUE – the URL, the category name, or ""
# Globals instead of stdout: fuzzel must own the terminal-free display and a
# $() capture would also swallow the die-path notifications.
PICK_TYPE="none"
PICK_VALUE=""

_pick_entry() {
    local prompt="$1" sel=""

    # fuzzel refuses to start when another instance is already up (e.g. the
    # app launcher is open) and exits instantly — which looks exactly like a
    # dead keybind.  Detect and report instead.
    if pgrep -x fuzzel >/dev/null 2>&1; then
        die "fuzzel is already running; close it and retry" 1
    fi

    sel=$(_grouped_menu | fuzzel --dmenu \
        --prompt="$prompt" \
        --placeholder="fuzzy-search tabs; headings group by category") || true

    if [[ -z "$sel" ]]; then
        PICK_TYPE="none"; PICK_VALUE=""
    elif [[ "$sel" == "$EDIT_ROW" ]]; then
        PICK_TYPE="edit"; PICK_VALUE=""
    elif [[ "$sel" == "── "*" ──" ]]; then
        PICK_VALUE="${sel#── }"
        PICK_VALUE="${PICK_VALUE% ──}"
        PICK_TYPE="category"
    else
        PICK_VALUE="${sel#  }"
        PICK_TYPE="url"
    fi
}

# Resolve the category for a new freeze: use the explicit CLI argument when
# given, otherwise offer existing categories in fuzzel (free text creates a
# new one; Escape/empty → DEFAULT_CATEGORY).  Tabs/newlines are scrubbed —
# they are the DB's field/record separators.
_resolve_category() {
    local cat="${1:-}"

    if [[ -z "$cat" ]] && command -v fuzzel >/dev/null 2>&1 \
        && ! pgrep -x fuzzel >/dev/null 2>&1; then
        cat=$(_existing_categories | fuzzel --dmenu \
            --prompt="❄ category › " \
            --placeholder="pick or type new; Esc → ${DEFAULT_CATEGORY}") || true
    fi

    cat="${cat//$'\t'/ }"
    cat="${cat//$'\n'/ }"
    cat="${cat#"${cat%%[![:space:]]*}"}"   # trim leading whitespace
    cat="${cat%"${cat##*[![:space:]]}"}"   # trim trailing whitespace
    printf '%s' "${cat:-$DEFAULT_CATEGORY}"
}

# ─── Subcommand: ice ─────────────────────────────────────────────────────────

# 1. Resolve active browser + grab its current tab URL
# 2. Validate; for new URLs resolve a category (CLI arg or fuzzel prompt) and
#    append URL<TAB>browser<TAB>category to the flat-file DB
# 3. SIGTERM the browser process to free all resident memory — but ONLY when
#    the URL came from a verified browser grab.  A clipboard-fallback URL may
#    be stale garbage; killing the browser on it silently discards the tab
#    the user actually wanted frozen ("my tabs didn't survive").
cmd_ice() {
    local category="${1:-}"

    init_db
    require_commands "wl-paste" "pgrep"

    local url browser
    browser=$(_detect_browser)
    resolve_url "$browser"
    url="$GRAB_URL"

    [[ "$url" =~ ^https?:// ]] || die "Not a valid HTTP/S URL: ${url}" 1

    # Idempotency on the URL (parsed from the Markdown, so hand-added bullets
    # count too); duplicates would render twice in the menus
    local is_dup=0
    if _db_entries | URL="$url" awk -F'\t' \
        '$1==ENVIRON["URL"]{f=1;exit} END{exit f?0:1}'; then
        is_dup=1
    fi

    local froze_new=0
    if (( is_dup )); then
        print_warn "Already frozen (skipping duplicate): ${url}"
        log_warn "Duplicate skipped: ${url}"
        _notify low "iced ❄ duplicate" "Already frozen: ${url}"
    else
        # Category is only worth asking for when we are actually appending;
        # prompting on duplicates would be a pointless extra dialog
        category=$(_resolve_category "$category")

        # Serialize the bullet; the origin-browser comment is omitted for
        # clipboard-mode freezes (they reopen via xdg-open anyway)
        local entry="- ${url}"
        [[ "$browser" != "clipboard" ]] && entry+=" <!--${browser}-->"

        # Insert at the TOP of the matching section (newest first, mirrors the
        # menu); create the section at EOF when it doesn't exist yet.  Heading
        # match is normalized exactly like the reader, so hand-written
        # variants ("##  work ") still match.  One blank line directly under
        # the heading is swallowed to keep the bullet list contiguous.
        CAT="$category" ENTRY="$entry" _db_rewrite '
            /^##[[:space:]]/ && !ins && md_heading($0) == ENVIRON["CAT"] {
                print
                print ENVIRON["ENTRY"]
                ins = 1
                swallow = 1
                next
            }
            swallow { swallow = 0; if ($0 ~ /^[[:space:]]*$/) next }
            { print }
            END {
                if (!ins) {
                    print ""
                    print "## " ENVIRON["CAT"]
                    print ENVIRON["ENTRY"]
                }
            }'
        print_success "Frozen [${category}]: ${url}"
        log_success "Frozen [${category}]: ${url}"
        froze_new=1
    fi

    if [[ "$browser" == "clipboard" ]]; then
        # Plain-clipboard mode: no browser context to terminate.
        # Explicit if — a bare `(( )) &&` list here would make the function
        # return 1 on duplicates under set -e.
        if (( froze_new )); then
            _notify normal "iced ❄" "Frozen from clipboard [${category}]: ${url}"
        fi
    elif [[ "$GRAB_SOURCE" == "primary" ]]; then
        # Kill even on duplicate: the URL is safe in the DB either way and
        # the user's intent is reclaiming the browser's RAM
        kill_browser "$browser"
        if (( froze_new )); then
            _notify normal "iced ❄" "Frozen [${category}] (${browser} terminated): ${url}"
        else
            _notify normal "iced ❄" "${browser} terminated (already frozen): ${url}"
        fi
    else
        # Unverified URL → refuse to kill; tell the user loudly so a stale
        # clipboard freeze can't masquerade as a successful ice
        log_warn "URL came from clipboard fallback; NOT killing ${browser}"
        print_warn "Unverified (clipboard) URL saved; ${browser} left running"
        _notify critical "iced ❄ unverified" \
            "Saved from clipboard — could not read ${browser}'s active tab, so it was NOT killed: ${url}"
    fi
}

# ─── Subcommand: thaw ────────────────────────────────────────────────────────

# 1. Grouped fuzzel menu (category sub-headings, most recent first)
# 2. Launch the URL in the browser it was frozen from and disown the child
#
# Thaw is NON-destructive: the entry stays in the DB until explicitly deleted
# via `remove`.  No browser detection runs here either — the origin browser is
# read from the entry itself (col 2); entries without one go straight to
# xdg-open instead of probing every browser process on the system.
cmd_thaw() {
    init_db
    require_commands "fuzzel" "awk" "pgrep"

    if [[ -z "$(_db_entries)" ]]; then
        # From a keybind an empty DB is indistinguishable from a dead bind
        # unless we say something
        _notify normal "iced" "No frozen tabs in the database"
        print_warn "Tab database is empty; nothing to thaw."
        exit 0
    fi

    _pick_entry "❄ thaw › "

    case "$PICK_TYPE" in
        none)
            log_info "Thaw aborted: no selection made"
            exit 0
            ;;
        edit)
            cmd_edit
            exit 0
            ;;
        category)
            _notify low "iced" "'${PICK_VALUE}' is a heading — pick a tab to thaw"
            print_warn "Headings cannot be thawed; pick a tab"
            exit 0
            ;;
    esac
    local url="$PICK_VALUE"

    # Recover the origin browser recorded at ice time (the <!--browser-->
    # comment, surfaced as col 2 of the parsed stream).  ENVIRON avoids awk -v
    # backslash-escape mangling of arbitrary URL bytes.
    local browser=""
    browser=$(_db_entries | SEL="$url" awk -F'\t' \
        '$1==ENVIRON["SEL"] {print $2; exit}') || true

    # Bullets without an origin browser (hand-added or clipboard-frozen) →
    # xdg-open via the "clipboard" sentinel.  Deliberately NO live detection:
    # probing every browser here made thaw slow and the guess was wrong
    # whenever several were installed.
    local via="$browser"
    if [[ -z "$browser" || "$browser" == "clipboard" ]]; then
        browser="clipboard"
        via="default browser"
    fi

    _launch_in "$browser" "$url"

    log_info "Thawed (kept in DB): ${url}"
    print_success "Launched: ${url}"
    _notify normal "iced 🔥" "Thawed in ${via} (kept in list): ${url}"
}

# Launch a URL in the given canonical browser, trying each installed binary
# alternative in order; unknown browsers and the "clipboard" sentinel
# degrade to xdg-open (honours \$BROWSER and desktop mimeinfo).
_launch_in() {
    local browser="$1" url="$2"
    local -a candidates=()

    case "$browser" in
        qutebrowser) candidates=( qutebrowser ) ;;
        firefox)     candidates=( firefox firefox-esr librewolf ) ;;
        chromium)    candidates=( chromium chromium-browser google-chrome-stable google-chrome ) ;;
        brave)       candidates=( brave brave-browser ) ;;
    esac

    local c
    for c in "${candidates[@]}"; do
        if command -v "$c" >/dev/null 2>&1; then
            "$c" "$url" >/dev/null 2>&1 & disown
            log_info "Launched via ${c}: ${url}"
            return 0
        fi
    done

    command -v xdg-open >/dev/null 2>&1 || die "No browser found to open: ${url}" 1
    log_warn "Browser '${browser}' unavailable; delegating to xdg-open"
    xdg-open "$url" >/dev/null 2>&1 & disown
}

# ─── Subcommand: remove ──────────────────────────────────────────────────────

# Explicit deletion — the only scripted operation that shrinks the DB now that
# thaw is non-destructive (the edit subcommand covers bulk changes).  Same
# grouped menu as thaw with one extra power:
#   - pick a tab      → that bullet is purged
#   - pick a heading  → the ENTIRE section (heading + bullets) is purged
cmd_remove() {
    init_db
    require_commands "fuzzel" "awk" "mktemp" "pgrep"

    if [[ -z "$(_db_entries)" ]]; then
        _notify normal "iced" "No frozen tabs in the database"
        print_warn "Tab database is empty; nothing to remove."
        exit 0
    fi

    _pick_entry "✂ remove › "

    case "$PICK_TYPE" in
        none)
            log_info "Remove aborted: no selection made"
            exit 0
            ;;
        edit)
            cmd_edit
            exit 0
            ;;
        category)
            local before after removed
            before=$(_db_entries | wc -l)
            # Drop everything from the matching heading up to (not including)
            # the next heading or EOF.  Headings are normalized exactly like
            # the menu, so the selected heading always matches its section.
            # Bullets ABOVE the first heading parse as DEFAULT_CATEGORY, so
            # removing that category also sweeps them — without touching the
            # title/prose around them.
            CAT="$PICK_VALUE" DEF="$DEFAULT_CATEGORY" _db_rewrite '
                BEGIN { pre = (ENVIRON["CAT"] == ENVIRON["DEF"]) }
                /^##[[:space:]]/ {
                    pre = 0
                    skip = (md_heading($0) == ENVIRON["CAT"])
                }
                pre && /^[-*][[:space:]]/ { next }
                !skip { print }'
            after=$(_db_entries | wc -l)
            removed=$(( before - after ))
            log_info "Removed category '${PICK_VALUE}' (${removed} tab(s))"
            print_success "Removed category '${PICK_VALUE}' (${removed} tab(s))"
            _notify normal "iced ✂" "Removed category '${PICK_VALUE}' (${removed} tab(s))"
            ;;
        url)
            # Delete only the bullet whose PARSED url matches — comment and
            # markdown-link decorations on the line don't affect the match
            SEL="$PICK_VALUE" _db_rewrite '
                /^[-*][[:space:]]/ && md_url($0) == ENVIRON["SEL"] { next }
                { print }'
            log_info "Removed from DB: ${PICK_VALUE}"
            print_success "Removed: ${PICK_VALUE}"
            _notify normal "iced ✂" "Removed: ${PICK_VALUE}"
            ;;
    esac
}

# ─── Subcommand: edit ────────────────────────────────────────────────────────

# Open the Markdown DB for manual bulk management.  Reachable from the CLI and
# from the pinned "✎ edit tab list" row in every picker menu.
#   1. $ICED_EDITOR override (may embed args: ICED_EDITOR="ghostty -e nvim")
#   2. attached terminal → $EDITOR inline (blocks until done)
#   3. journal.sh surface-tabs → focuses the journal-managed "Journal Tabs"
#      window (or opens it) so every entry point shares one window
#   4. last resort: spawn $TERMINAL (or a known terminal) around $EDITOR
cmd_edit() {
    init_db

    if [[ -n "${ICED_EDITOR:-}" ]]; then
        # word-split intentional: the override may carry its own arguments
        ${ICED_EDITOR} "$TAB_DB" >/dev/null 2>&1 & disown
        log_info "Opened DB via ICED_EDITOR: ${ICED_EDITOR}"
        _notify low "iced ✎" "Opened tab list in ${ICED_EDITOR%% *}"
        return 0
    fi

    if [[ -t 0 ]]; then
        ${EDITOR:-vi} "$TAB_DB"
        log_info "Edited DB inline via ${EDITOR:-vi}"
        return 0
    fi

    # Keybind context: hand off to the journal system, which owns the
    # canonical editor window for this file (focus-or-launch semantics)
    if [[ -x "$ICED_JOURNAL" ]]; then
        if "$ICED_JOURNAL" surface-tabs >/dev/null 2>&1; then
            log_info "Surfaced tab list via ${ICED_JOURNAL} surface-tabs"
            _notify low "iced ✎" "Tab list surfaced in the journal"
            return 0
        fi
        log_warn "journal.sh surface-tabs failed; falling back to a raw terminal"
    fi

    # No terminal attached and no journal integration: wrap $EDITOR ourselves
    local term
    for term in "${TERMINAL:-}" ghostty foot alacritty kitty; do
        if [[ -n "$term" ]] && command -v "$term" >/dev/null 2>&1; then
            "$term" -e ${EDITOR:-nvim} "$TAB_DB" >/dev/null 2>&1 & disown
            log_info "Opened DB in ${term} -e ${EDITOR:-nvim}"
            _notify low "iced ✎" "Opened tab list in ${term}"
            return 0
        fi
    done

    die "No terminal emulator found; set ICED_EDITOR or TERMINAL" 1
}

# ─── Usage ───────────────────────────────────────────────────────────────────

usage() {
    # printf '%b' interprets the \033[ escape sequences stored as literal
    # strings in colors.sh; a bare cat<<EOF would print them raw
    printf '%b\n' "$(cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") <command> [args]

${BOLD}Commands:${RESET}
  ${SUCCESS}ice [category]${RESET}  Grab active browser tab URL → freeze to DB → kill browser
                  (category from arg, else fuzzel prompt; Esc → ${DEFAULT_CATEGORY})
  ${INFO}thaw${RESET}            fuzzel-select a frozen tab → reopen in its origin browser
                  (non-destructive: the entry stays listed until removed)
  ${ERROR}remove${RESET}          fuzzel-select a tab to delete — or a ${BOLD}heading${RESET} to delete
                  that entire section
  ${WARN}edit${RESET}            open the Markdown DB in \$EDITOR for bulk management
                  (also pinned as "${EDIT_ROW}" in every menu;
                   override launcher: ICED_EDITOR="ghostty -e nvim")

${BOLD}Menu:${RESET} tabs are grouped under ── category ── sub-headings in FILE order —
rearrange the Markdown by hand and the menus follow.

${BOLD}Browser auto-detection (ice only):${RESET}
  Priority: \$ICED_BROWSER env > hyprctl activewindow class > process probe > clipboard
  Supported: qutebrowser (IPC), firefox (ydotool), chromium/brave (CDP port ${CDP_PORT}, then ydotool)
  Override:  ICED_BROWSER=firefox iced.sh ice work
  Safety:    the browser is only killed when its active tab was read directly;
             a raw-clipboard fallback URL is saved but never triggers a kill.
  Feedback:  every outcome raises a notify-send notification (keybind-safe).

${BOLD}Database:${RESET} ${TAB_DB}
  Markdown: '## category' headings, '- URL <!--browser-->' bullets.
  Hand-edit freely; plain '- URL' bullets and '[title](url)' links both parse.
  Lives in the journal repo (git-backed); linked from the journal dashboard
  and openable via 'journal.sh tabs' / 'journal.sh surface-tabs'.
  Override the location with ICED_DB (or JOURNAL_DIR for the repo root).

${BOLD}Hyprland keybinds (managed in configs/keybinds.lua):${RESET}
  hl.bind(mod_shift("I"), hl.dsp.exec_cmd("~/.local/bin/launcher/iced.sh ice"))
  hl.bind(mod_shift("T"), hl.dsp.exec_cmd("~/.local/bin/launcher/iced.sh thaw"))
  hl.bind(mod_shift("R"), hl.dsp.exec_cmd("~/.local/bin/launcher/iced.sh remove"))
EOF
)"
}

# ─── Entrypoint ──────────────────────────────────────────────────────────────

case "${1:-}" in
    ice)            cmd_ice "${2:-}" ;;
    thaw)           cmd_thaw   ;;
    remove)         cmd_remove ;;
    edit)           cmd_edit   ;;
    -h|--help|help) usage; exit 0 ;;
    *)              usage >&2; exit 1 ;;
esac
