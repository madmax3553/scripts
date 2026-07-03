#!/usr/bin/env python3
import argparse
import html
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import date
from html.parser import HTMLParser
from http.cookiejar import MozillaCookieJar

import requests


READLIST_PATH = os.path.expanduser("~/projects/journal/notes/readlist.md")
IMPORT_HEADING = "## Imported from Audible (Needs metadata)"
SYNC_HEADING = "### Sync Status (Audible)"
ACQUISITION_HEADING = "### Acquisition Backlog (Not Owned Yet)"
ARCHIVE_HEADING = "## Archive"
FINISHED_UNRATED_HEADING = "### Finished - Unrated"
ENTRY_PATTERN = re.compile(
    r"^(\s*-\s+\[([ xX])\]\s+\*\*([^*]+)\*\*(?:\s+\(([^)]+)\))?)(.*)$"
)
METADATA_SUBITEM_PATTERN = re.compile(r"^\s+-\s+\*(Author|Series|Summary):\*\s*(.+?)\s*$")
BACK_TO_DASHBOARD = "*Back to [[index|Dashboard]]*"

DEFAULT_READLIST = """# Readlist

* **Source:** Audible Library import

---

## Workflow

- `[ ]` = active read candidate.
- `[x]` = finished; move it to the archive after adding a rating.
- Rating format: `TBD/5` until scored, then `1/5` through `5/5`.
- `journal.sh readlist import --audible-html /path/to/library.html` imports Audible titles.
- `journal.sh readlist import --fetch-audible-browser --audible-domain www.audible.ca` imports via persistent browser session.
- `journal.sh readlist import --fetch-audible-api --audible-cookie-file /path/to/cookies.txt` imports all pages from Audible API.
- `journal.sh readlist archive` archives checked entries without importing.

## Rating Scale

- `5/5` Favorite; would reread.
- `4/5` Strong recommend.
- `3/5` Worth reading.
- `2/5` Not for me, but had something.
- `1/5` Skip.

---

## Books to Read

## Imported from Audible (Needs metadata)

---

## Archive

### Finished - Unrated

---

*Back to [[index|Dashboard]]*
"""

STOPWORDS = {
    "audible",
    "your library",
    "library",
    "wishlist",
    "browse",
    "search",
    "sort by",
    "filter",
}

AUDIBLE_API_RESPONSE_GROUPS = "contributors,media,product_attrs,product_desc"


@dataclass(frozen=True)
class ReadItem:
    idx: int
    checkbox: str
    clean_line: str
    title: str
    info: str | None
    old_suffix: str

    @property
    def checked(self) -> bool:
        return self.checkbox.lower() == "x"


@dataclass(frozen=True)
class AudibleFetchedItem:
    title: str
    author: str | None = None
    series: str | None = None
    summary: str | None = None


class AudibleLibraryParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.in_anchor = False
        self.anchor_text = []
        self.titles = []

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        attrs = dict(attrs)
        href = attrs.get("href", "") or ""
        if "/pd/" in href or "titleId=" in href:
            self.in_anchor = True
            self.anchor_text = []

    def handle_data(self, data):
        if self.in_anchor:
            self.anchor_text.append(data)

    def handle_endtag(self, tag):
        if tag != "a" or not self.in_anchor:
            return
        raw = "".join(self.anchor_text)
        title = normalize_title(raw)
        if title:
            self.titles.append(title)
        self.in_anchor = False
        self.anchor_text = []


def normalize_title(text):
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    text = text.strip("-| ")
    if not text:
        return ""
    folded = text.casefold()
    if folded in STOPWORDS:
        return ""
    if re.fullmatch(r"\d+", text):
        return ""
    return text


def canonical_title(text):
    text = normalize_title(text)
    text = text.replace("atLarge", "at Large")
    text = re.sub(
        r":\s*([^:]+,\s*Book\s*\d+)\s*:\s*\1\s*$",
        r": \1",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(r"\s+", " ", text).strip()
    return text


def title_match_key(text):
    text = canonical_title(text).casefold()
    # Collapse noisy variant markers that often differ between Audible surfaces.
    text = re.sub(r"\(narrated by [^)]+\)", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\bunabridged\b", "", text, flags=re.IGNORECASE)
    text = text.replace("&", "and")
    text = re.sub(r"[^a-z0-9]+", "", text)
    return text


def base_title_match_key(text):
    text = canonical_title(text)
    base = text.split(":", 1)[0].strip()
    base = re.sub(r"\b(a novel|unabridged)\b", "", base, flags=re.IGNORECASE)
    base = re.sub(r"\s+", " ", base).strip()
    if not base:
        return ""
    base = base.casefold().replace("&", "and")
    base = re.sub(r"[^a-z0-9]+", "", base)
    return base


def normalize_author(text):
    text = html.unescape(str(text or ""))
    text = re.sub(r"\s+", " ", text).strip(" ,;|-")
    text = re.sub(r"^(written by:|by:)\s*", "", text, flags=re.IGNORECASE).strip()
    if "narrated by" in text.casefold():
        return ""
    if text.endswith(")"):
        text = text.rstrip(")").strip()
    return text


def normalize_summary(text):
    text = html.unescape(str(text or ""))
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return ""
    if re.search(r"audible,\s*inc\.", text, flags=re.IGNORECASE):
        return ""
    if re.search(r"\b1-888-\d{3}-\d{4}\b", text):
        return ""
    if re.match(r"^narrated by:", text, flags=re.IGNORECASE):
        return ""
    max_len = 360
    if len(text) <= max_len:
        return text
    clipped = text[:max_len].rsplit(" ", 1)[0].strip()
    return f"{clipped}…"


def normalize_series(text):
    text = html.unescape(str(text or ""))
    text = re.sub(r"\s+", " ", text).strip(" ,;|-")
    return text


def parse_args():
    parser = argparse.ArgumentParser(
        description="Import Audible Library titles into readlist and archive checked items."
    )
    parser.add_argument(
        "--readlist",
        default=READLIST_PATH,
        help=f"Readlist markdown file to update. Default: {READLIST_PATH}",
    )
    parser.add_argument(
        "--audible-html",
        help="Saved Audible library HTML file to import from.",
    )
    parser.add_argument(
        "--fetch-audible-api",
        action="store_true",
        help="Fetch your Audible library directly from Audible API instead of HTML export.",
    )
    parser.add_argument(
        "--fetch-audible-browser",
        action="store_true",
        help=(
            "Fetch Audible library using a persistent browser session "
            "(recommended, avoids cookie export issues)."
        ),
    )
    parser.add_argument(
        "--audible-domain",
        default="www.audible.com",
        help="Audible host to query (for example: www.audible.com, www.audible.ca).",
    )
    parser.add_argument(
        "--audible-cookie-file",
        action="append",
        help=(
            "Netscape cookie file(s) for Audible/Amazon auth (repeatable). "
            "Example: --audible-cookie-file audible.txt --audible-cookie-file amazon.txt"
        ),
    )
    parser.add_argument(
        "--audible-cookie-header",
        help="Raw Cookie header value for Audible auth.",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=50,
        help="Audible API page size per request. Default: 50.",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=200,
        help="Safety cap on Audible API pages to fetch. Default: 200.",
    )
    parser.add_argument(
        "--browser-profile-dir",
        default="~/.local/share/audible-playwright-profile",
        help="Persistent Playwright profile dir for Audible login session.",
    )
    parser.add_argument(
        "--browser-headless",
        action="store_true",
        help="Run browser mode headless (works after initial login is established).",
    )
    parser.add_argument(
        "--no-import",
        action="store_true",
        help="Skip importing from Audible HTML.",
    )
    parser.add_argument(
        "--sync",
        action="store_true",
        help=(
            "Compare fetched Audible titles against current readlist owned set, "
            "append newly owned titles, update sync status report, and enrich missing metadata."
        ),
    )
    parser.add_argument(
        "--archive-finished",
        action="store_true",
        help="Move checked read items from active sections into the archive.",
    )
    parser.add_argument(
        "--finished-date",
        default=date.today().isoformat(),
        help="Date to write for newly archived items. Default: today.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print detected titles and exit without writing.",
    )
    return parser.parse_args()


def find_heading(lines, heading, start=0):
    for idx in range(start, len(lines)):
        if lines[idx].strip() == heading:
            return idx
    return None


def find_next_h2(lines, start):
    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("## "):
            return idx
    return len(lines)


def find_next_h3(lines, start):
    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("### "):
            return idx
    return len(lines)


def split_footer(lines):
    for idx in range(len(lines) - 1, -1, -1):
        if lines[idx].strip() != BACK_TO_DASHBOARD:
            continue

        footer_start = idx
        if idx >= 2 and lines[idx - 1].strip() == "" and lines[idx - 2].strip() == "---":
            footer_start = idx - 2
        return lines[:footer_start], lines[footer_start:]

    return lines, []


def ensure_readlist_structure(lines):
    if find_heading(lines, IMPORT_HEADING) is None:
        insert_at = find_heading(lines, ARCHIVE_HEADING)
        if insert_at is None:
            body, footer = split_footer(lines)
            insert_at = len(body)
            lines = body + footer
        block = ["\n", f"{IMPORT_HEADING}\n", "\n"]
        lines = lines[:insert_at] + block + lines[insert_at:]

    if find_heading(lines, ARCHIVE_HEADING) is None:
        lines.extend(["\n", "---\n", "\n", f"{ARCHIVE_HEADING}\n", "\n", f"{FINISHED_UNRATED_HEADING}\n", "\n"])

    return lines


def parse_items(lines):
    items = []
    for idx, line in enumerate(lines):
        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if not match:
            continue
        full_prefix, checkbox, title, info, suffix = match.groups()
        items.append(
            ReadItem(
                idx=idx,
                checkbox=checkbox,
                clean_line=full_prefix.rstrip(),
                title=title.strip(),
                info=info.strip() if info else None,
                old_suffix=suffix.strip(),
            )
        )
    return items


def read_existing_title_keys(lines):
    keys = set()
    for item in parse_items(lines):
        info_key = (item.info or "").casefold()
        keys.add((item.title.casefold(), info_key))
    return keys


def escape_markdown_title(title):
    return title.replace("\\", "\\\\").replace("*", r"\*")


def insert_imported_titles(lines, titles):
    if not args.sync:
        lines = ensure_readlist_structure(lines)
    heading_idx = find_heading(lines, IMPORT_HEADING)
    if heading_idx is None:
        return lines, 0

    end_idx = find_next_h2(lines, heading_idx)
    existing_titles = {canonical_title(item.title).casefold() for item in parse_items(lines)}
    additions = []
    for raw_title in titles:
        title = canonical_title(raw_title)
        key = title.casefold()
        if key in existing_titles:
            continue
        additions.append(f"- [ ] **{escape_markdown_title(title)}**\n")
        existing_titles.add(key)

    if not additions:
        return lines, 0

    insert_at = heading_idx + 1
    while insert_at < end_idx and lines[insert_at].strip() == "":
        insert_at += 1

    section = additions + ["\n"]
    return lines[:insert_at] + section + lines[insert_at:], len(additions)


def collect_imported_owned_titles(lines):
    imported_idx = find_heading(lines, IMPORT_HEADING)
    if imported_idx is None:
        return {}
    end_idx = find_next_h2(lines, imported_idx)

    owned = {}
    in_acquisition = False
    in_sync = False
    for line in lines[imported_idx:end_idx]:
        stripped = line.strip()
        if stripped == ACQUISITION_HEADING:
            in_acquisition = True
            continue
        if in_acquisition and stripped.startswith("### ") and stripped != ACQUISITION_HEADING:
            in_acquisition = False
        if stripped == SYNC_HEADING:
            in_sync = True
            continue
        if in_sync and stripped.startswith("### ") and stripped != SYNC_HEADING:
            in_sync = False

        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if not match:
            continue
        _full_prefix, _checkbox, title, _info, suffix = match.groups()
        suffix = (suffix or "").casefold()
        if in_sync or in_acquisition or "🛒" in suffix:
            continue
        title_clean = canonical_title(title.strip())
        owned[title_clean.casefold()] = title_clean

    archive_idx = find_heading(lines, ARCHIVE_HEADING)
    if archive_idx is not None:
        archive_end = find_next_h2(lines, archive_idx)
        for line in lines[archive_idx:archive_end]:
            match = ENTRY_PATTERN.match(line.rstrip("\n"))
            if not match:
                continue
            _full_prefix, _checkbox, title, _info, _suffix = match.groups()
            title_clean = canonical_title(title.strip())
            owned[title_clean.casefold()] = title_clean

    return owned


def collect_acquisition_titles(lines):
    idx = find_heading(lines, ACQUISITION_HEADING)
    if idx is None:
        return []
    end = len(lines)
    for i in range(idx + 1, len(lines)):
        if lines[i].startswith("### ") and lines[i].strip() != ACQUISITION_HEADING:
            end = i
            break

    titles = []
    for line in lines[idx:end]:
        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if not match:
            continue
        _full_prefix, _checkbox, title, _info, _suffix = match.groups()
        title = canonical_title(title.strip())
        if title:
            titles.append(title)
    return titles


def collect_archive_titles(lines):
    archive_idx = find_heading(lines, ARCHIVE_HEADING)
    if archive_idx is None:
        return []
    archive_end = find_next_h2(lines, archive_idx)
    titles = []
    for line in lines[archive_idx:archive_end]:
        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if not match:
            continue
        _full_prefix, _checkbox, title, _info, _suffix = match.groups()
        title = canonical_title(title.strip())
        if title:
            titles.append(title)
    return titles


def collect_checked_titles(lines):
    checked = []
    stop_at = find_heading(lines, ARCHIVE_HEADING)
    limit = stop_at if stop_at is not None else len(lines)
    for line in lines[:limit]:
        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if not match:
            continue
        _full_prefix, checkbox, title, _info, suffix = match.groups()
        if checkbox.lower() != "x":
            continue
        if "🛒" in (suffix or ""):
            continue
        title = canonical_title(title.strip())
        if title:
            checked.append(title)
    return checked


def build_sync_section_lines(sync_date, fetched_count, known_count, new_titles, missing_titles):
    lines = [
        f"{SYNC_HEADING}\n",
        f"- *Last sync:* {sync_date}\n",
        f"- *Fetched from Audible:* {fetched_count}\n",
        f"- *Known owned in readlist before sync:* {known_count}\n",
        f"- *Newly owned detected:* {len(new_titles)}\n",
        f"- *Previously tracked but not seen now:* {len(missing_titles)}\n",
        "\n",
    ]

    if new_titles:
        lines.append("#### Newly Owned (added this sync)\n")
        for title in new_titles:
            lines.append(f"- [ ] **{title}**\n")
        lines.append("\n")

    if missing_titles:
        lines.append("#### Missing from Current Audible Pull (review)\n")
        for title in missing_titles:
            lines.append(f"- [ ] **{title}**\n")
        lines.append("\n")

    return lines


def upsert_sync_section(lines, section_lines):
    imported_idx = find_heading(lines, IMPORT_HEADING)
    if imported_idx is None:
        return lines, False
    imported_end = find_next_h2(lines, imported_idx)

    existing_sync_idx = find_heading(lines, SYNC_HEADING, imported_idx)
    if existing_sync_idx is not None and existing_sync_idx < imported_end:
        sync_end = imported_end
        for idx in range(existing_sync_idx + 1, imported_end):
            if lines[idx].startswith("### "):
                sync_end = idx
                break
        updated = lines[:existing_sync_idx] + section_lines + lines[sync_end:]
    else:
        insert_at = find_heading(lines, ACQUISITION_HEADING, imported_idx)
        if insert_at is None or insert_at >= imported_end:
            insert_at = imported_idx + 1
            while insert_at < imported_end and lines[insert_at].strip() == "":
                insert_at += 1
        prefix = []
        if insert_at > 0 and lines[insert_at - 1].strip() != "":
            prefix.append("\n")
        updated = lines[:insert_at] + prefix + section_lines + lines[insert_at:]

    changed = "".join(updated) != "".join(lines)
    return updated, changed


def item_key_from_match(match):
    _full_prefix, _checkbox, title, info, _suffix = match.groups()
    return title.strip().casefold(), (info or "").strip().casefold()


def archived_item_keys(lines):
    archive_idx = find_heading(lines, ARCHIVE_HEADING)
    if archive_idx is None:
        return set()

    end_idx = find_next_h2(lines, archive_idx)
    keys = set()
    for line in lines[archive_idx:end_idx]:
        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if match:
            keys.add(item_key_from_match(match))
    return keys


def collect_item_block(lines, start):
    end = start + 1
    while end < len(lines):
        stripped = lines[end].strip()
        if lines[end].startswith("## ") or stripped == "---":
            break
        if ENTRY_PATTERN.match(lines[end].rstrip("\n")):
            break
        end += 1

    block = lines[start:end]
    while block and block[-1].strip() == "":
        block.pop()
        end -= 1
    return block, end


def archive_search_limit(lines):
    candidates = [
        idx for idx in [find_heading(lines, ARCHIVE_HEADING)] if idx is not None
    ]
    return min(candidates) if candidates else len(lines)


def normalize_checked_line(line):
    return re.sub(r"^(\s*-\s+\[)[xX](\])", r"\1x\2", line, count=1)


def archive_block(block, finished_date):
    if not block:
        return []

    first = normalize_checked_line(block[0])
    rest = block[1:]
    has_rating = any("*Rating:*" in line for line in rest)
    has_finished = any("*Finished:*" in line for line in rest)
    has_reread = any("*Reread:*" in line for line in rest)

    fields = []
    if not has_rating:
        fields.append("    - *Rating:* TBD/5\n")
    if not has_finished:
        fields.append(f"    - *Finished:* {finished_date}\n")
    if not has_reread:
        fields.append("    - *Reread:* TBD\n")

    return [first] + fields + rest + ["\n"]


def insert_archive_blocks(lines, blocks):
    if not blocks:
        return lines

    archive_idx = find_heading(lines, ARCHIVE_HEADING)
    if archive_idx is None:
        lines = ensure_readlist_structure(lines)
        archive_idx = find_heading(lines, ARCHIVE_HEADING)
        if archive_idx is None:
            return lines

    archive_end = find_next_h2(lines, archive_idx)
    target_idx = find_heading(lines, FINISHED_UNRATED_HEADING, archive_idx)
    if target_idx is None or target_idx >= archive_end:
        insert_at = archive_idx + 1
        while insert_at < len(lines) and lines[insert_at].strip() == "":
            insert_at += 1
        section = ["\n", f"{FINISHED_UNRATED_HEADING}\n", "\n"]
        for block in blocks:
            section.extend(block)
        return lines[:insert_at] + section + lines[insert_at:]

    insert_at = target_idx + 1
    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1

    section = []
    for block in blocks:
        section.extend(block)

    return lines[:insert_at] + section + lines[insert_at:]


def archive_finished_items(lines, finished_date):
    existing_archive_keys = archived_item_keys(lines)
    limit = archive_search_limit(lines)
    new_lines = []
    archive_blocks = []
    idx = 0

    while idx < len(lines):
        if idx < limit:
            match = ENTRY_PATTERN.match(lines[idx].rstrip("\n"))
            if match and match.group(2).lower() == "x":
                block, end = collect_item_block(lines, idx)
                key = item_key_from_match(match)
                if key not in existing_archive_keys:
                    archive_blocks.append(archive_block(block, finished_date))
                    existing_archive_keys.add(key)
                idx = end
                continue

        new_lines.append(lines[idx])
        idx += 1

    return insert_archive_blocks(new_lines, archive_blocks), len(archive_blocks)


def extract_titles_from_html(content):
    parser = AudibleLibraryParser()
    parser.feed(content)
    parser.close()

    json_titles = re.findall(r'"title"\s*:\s*"([^"]+)"', content)
    candidates = parser.titles + [normalize_title(item) for item in json_titles]

    deduped = []
    seen = set()
    for title in candidates:
        if not title:
            continue
        key = title.casefold()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(title)
    return deduped


def extract_titles_from_api_items(items):
    deduped = []
    seen = set()
    for item in items:
        raw_title = item.get("title", "")
        title = normalize_title(raw_title)
        if not title:
            continue
        key = title.casefold()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(title)
    return deduped


def extract_author_from_api_item(item):
    if not isinstance(item, dict):
        return None

    direct = normalize_author(item.get("author") or item.get("author_name"))
    if direct:
        return direct

    authors = item.get("authors")
    if isinstance(authors, list):
        names = []
        for author in authors:
            if isinstance(author, dict):
                name = normalize_author(author.get("name"))
            else:
                name = normalize_author(author)
            if name:
                names.append(name)
        if names:
            return ", ".join(dict.fromkeys(names))

    contributors = item.get("contributors")
    if isinstance(contributors, list):
        names = []
        for contributor in contributors:
            if not isinstance(contributor, dict):
                continue
            role = (contributor.get("role") or contributor.get("type") or "").casefold()
            if "author" not in role:
                continue
            name = normalize_author(contributor.get("name"))
            if name:
                names.append(name)
        if names:
            return ", ".join(dict.fromkeys(names))

    return None


def extract_summary_from_api_item(item):
    if not isinstance(item, dict):
        return None

    for key in ("summary", "publisher_summary", "description", "product_desc"):
        value = item.get(key)
        if isinstance(value, str):
            summary = normalize_summary(value)
            if summary:
                return summary
        if isinstance(value, dict):
            for nested_key in ("summary", "text", "value", "description"):
                summary = normalize_summary(value.get(nested_key))
                if summary:
                    return summary
    return None


def extract_series_from_api_item(item):
    if not isinstance(item, dict):
        return None

    direct = normalize_series(item.get("series") or item.get("series_name"))
    if direct:
        return direct

    series_list = item.get("series")
    if isinstance(series_list, list):
        names = []
        for entry in series_list:
            if isinstance(entry, dict):
                name = normalize_series(entry.get("title") or entry.get("name"))
            else:
                name = normalize_series(entry)
            if name:
                names.append(name)
        if names:
            return ", ".join(dict.fromkeys(names))

    return None


def extract_fetched_items_from_api_items(items):
    deduped = []
    seen = set()
    for item in items:
        title = normalize_title(item.get("title", "")) if isinstance(item, dict) else ""
        if not title:
            continue
        key = title.casefold()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(
            AudibleFetchedItem(
                title=title,
                author=extract_author_from_api_item(item),
                series=extract_series_from_api_item(item),
                summary=extract_summary_from_api_item(item),
            )
        )
    return deduped


def normalize_fetched_items(payload_items):
    normalized = []
    seen = set()
    for raw in payload_items:
        if isinstance(raw, str):
            title = canonical_title(raw)
            author = None
            series = None
            summary = None
        elif isinstance(raw, AudibleFetchedItem):
            title = canonical_title(raw.title)
            author = normalize_author(raw.author)
            series = normalize_series(raw.series)
            summary = normalize_summary(raw.summary)
        elif isinstance(raw, dict):
            title = canonical_title(raw.get("title", ""))
            author = normalize_author(raw.get("author"))
            series = normalize_series(raw.get("series"))
            summary = normalize_summary(raw.get("summary"))
        else:
            continue
        if not title:
            continue
        key = title.casefold()
        if key in seen:
            continue
        seen.add(key)
        normalized.append(
            AudibleFetchedItem(
                title=title,
                author=author or None,
                series=series or None,
                summary=summary or None,
            )
        )
    return normalized


def enrich_missing_metadata(lines, metadata_by_match_key):
    imported_idx = find_heading(lines, IMPORT_HEADING)
    if imported_idx is None:
        return lines, 0
    imported_end = find_next_h2(lines, imported_idx)
    author_section_idx = find_heading(
        lines, "### Author -> Universe -> Series (Priority Universes)", imported_idx
    )
    author_section_end = (
        find_next_h3(lines, author_section_idx)
        if author_section_idx is not None and author_section_idx < imported_end
        else None
    )

    updated = list(lines)
    enriched = 0
    idx = imported_idx

    while idx < imported_end:
        line = updated[idx]
        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if not match:
            idx += 1
            continue
        full_prefix, _checkbox, title, _info, suffix = match.groups()

        suffix_text = suffix or ""
        suffix_parts = [part.strip() for part in suffix_text.split(" — ") if part.strip()]
        kept_suffix_parts = []
        inline_meta = {}
        for part in suffix_parts:
            lower = part.casefold()
            if lower.startswith("author:"):
                inline_meta["author"] = part.split(":", 1)[1].strip()
            elif lower.startswith("series:"):
                inline_meta["series"] = part.split(":", 1)[1].strip()
            elif lower.startswith("summary:"):
                inline_meta["summary"] = part.split(":", 1)[1].strip()
            else:
                kept_suffix_parts.append(part)
        cleaned_suffix = f" — {' — '.join(kept_suffix_parts)}" if kept_suffix_parts else ""

        if cleaned_suffix != suffix_text:
            updated[idx] = f"{full_prefix}{cleaned_suffix}\n"

        metadata = metadata_by_match_key.get(title_match_key(title))
        metadata = metadata or {}

        in_author_scoped_section = (
            author_section_idx is not None
            and author_section_end is not None
            and author_section_idx < idx < author_section_end
        )

        existing_subitems = {}
        removed_subitems = False
        scan = idx + 1
        while scan < imported_end:
            submatch = METADATA_SUBITEM_PATTERN.match(updated[scan].rstrip("\n"))
            if submatch:
                label, value = submatch.groups()
                label_key = label.casefold()
                if in_author_scoped_section and label_key in {"author", "series"}:
                    del updated[scan]
                    imported_end -= 1
                    removed_subitems = True
                    continue
                existing_subitems[label_key] = value.strip()
                scan += 1
                continue
            break

        author = normalize_author(existing_subitems.get("author") or inline_meta.get("author") or metadata.get("author"))
        series = normalize_series(existing_subitems.get("series") or inline_meta.get("series") or metadata.get("series"))
        summary = normalize_summary(
            existing_subitems.get("summary") or inline_meta.get("summary") or metadata.get("summary")
        )
        title_norm = canonical_title(title).casefold()
        summary_norm = canonical_title(summary).casefold() if summary else ""
        if summary_norm == title_norm or summary_norm.startswith(title_norm):
            summary = ""

        additions = []
        if (
            author
            and "author" not in existing_subitems
            and not in_author_scoped_section
        ):
            additions.append(f"    - *Author:* {author}\n")
        if (
            series
            and "series" not in existing_subitems
            and not in_author_scoped_section
        ):
            additions.append(f"    - *Series:* {series}\n")
        if summary and "summary" not in existing_subitems:
            additions.append(f"    - *Summary:* {summary}\n")

        if not additions and cleaned_suffix == suffix_text and not removed_subitems:
            idx = scan
            continue

        if additions:
            updated[scan:scan] = additions
            imported_end += len(additions)
        enriched += 1
        idx = scan + len(additions)

    return updated, enriched


def session_from_cookie_sources(args):
    session = requests.Session()
    session.headers.update(
        {
            "Accept": "application/json",
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/126.0.0.0 Safari/537.36"
            ),
            "Referer": f"https://{args.audible_domain}/library/titles",
        }
    )

    cookie_sources = 0
    if args.audible_cookie_header:
        cookie_sources += 1
        for chunk in args.audible_cookie_header.split(";"):
            part = chunk.strip()
            if "=" not in part:
                continue
            key, value = part.split("=", 1)
            session.cookies.set(key.strip(), value.strip(), domain=args.audible_domain)

    if args.audible_cookie_file:
        cookie_sources += 1
        for cookie_file in args.audible_cookie_file:
            jar = MozillaCookieJar()
            jar.load(os.path.expanduser(cookie_file), ignore_discard=True, ignore_expires=True)
            for cookie in jar:
                domain = (cookie.domain or "").lower()
                if "audible" not in domain and "amazon" not in domain:
                    continue
                session.cookies.set(cookie.name, cookie.value, domain=cookie.domain, path=cookie.path)

    if cookie_sources == 0:
        raise ValueError(
            "Audible API mode requires --audible-cookie-file or --audible-cookie-header."
        )

    return session


def assert_authenticated_audible_session(session, domain):
    library_url = f"https://{domain}/library/titles"
    response = session.get(library_url, timeout=30, allow_redirects=True)
    final_url = (response.url or "").lower()
    body_prefix = (response.text or "")[:8000].lower()

    if "/ap/signin" in final_url or "amazon sign in" in body_prefix:
        raise RuntimeError(
            "Cookie auth is not valid for Audible web session. Re-export fresh cookies "
            "while logged into Audible and Amazon in the same browser profile."
        )


def normalize_audible_suffix(domain):
    domain = (domain or "").strip().lower()
    if domain.startswith("www."):
        return domain[4:]
    return domain


def audible_endpoint_candidates(domain):
    suffix = normalize_audible_suffix(domain)
    endpoints = [
        (f"https://www.{suffix}/api/library/titles", "page"),
        (f"https://api.{suffix}/1.0/library", "offset"),
    ]
    if suffix == "audible.com":
        endpoints.append(("https://api.audible.com/1.0/library", "offset"))
    return endpoints


def extract_payload_items(payload):
    if isinstance(payload, list):
        return payload
    if not isinstance(payload, dict):
        return []
    for key in ("items", "library", "products"):
        items = payload.get(key)
        if isinstance(items, list):
            return items
    return []


def payload_total_count(payload):
    if not isinstance(payload, dict):
        return None
    for key in ("total_results", "total_count", "total_items"):
        value = payload.get(key)
        if value is not None:
            try:
                return int(value)
            except (TypeError, ValueError):
                return None
    return None


def fetch_from_endpoint(session, base_url, mode, args):
    page = 1
    offset = 0
    next_url = None
    fetched_items = []
    seen = set()

    while page <= args.max_pages:
        if next_url:
            response = session.get(next_url, timeout=30)
        else:
            if mode == "offset":
                params = {
                    "num_results": args.page_size,
                    "offset": offset,
                    "content_type": "Audiobook",
                    "response_groups": AUDIBLE_API_RESPONSE_GROUPS,
                }
            else:
                params = {
                    "num_results": args.page_size,
                    "page": page,
                    "response_groups": AUDIBLE_API_RESPONSE_GROUPS,
                }
            response = session.get(base_url, params=params, timeout=30)

        if response.status_code in (401, 403):
            raise RuntimeError(
                f"Audible API auth failed ({response.status_code}). Refresh cookie export and retry."
            )
        if response.status_code == 404:
            raise RuntimeError(f"Endpoint not found: {base_url}")
        response.raise_for_status()

        payload = response.json()
        items = extract_payload_items(payload)
        if not items:
            break

        for fetched in extract_fetched_items_from_api_items(items):
            key = fetched.title.casefold()
            if key in seen:
                continue
            seen.add(key)
            fetched_items.append(fetched)

        total_count = payload_total_count(payload)
        print(f"Fetched page {page} from {base_url}: {len(items)} item(s).")

        if total_count and len(seen) >= int(total_count):
            break
        next_url = payload.get("next") if isinstance(payload, dict) else None
        if isinstance(next_url, str) and next_url.strip():
            page += 1
            continue

        if len(items) < args.page_size:
            break
        if mode == "offset":
            offset += args.page_size
        page += 1

    return fetched_items


def fetch_titles_from_audible_api(args):
    session = session_from_cookie_sources(args)
    assert_authenticated_audible_session(session, args.audible_domain)
    errors = []
    for base_url, mode in audible_endpoint_candidates(args.audible_domain):
        try:
            items = fetch_from_endpoint(session, base_url, mode, args)
            if items:
                return items
            errors.append(f"{base_url}: no titles returned")
        except Exception as exc:
            errors.append(f"{base_url}: {exc}")

    raise RuntimeError(" | ".join(errors))


def fetch_titles_from_audible_browser(args):
    helper_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fetch_audible_titles.cjs")
    if not os.path.exists(helper_path):
        raise RuntimeError(f"Node Audible helper not found: {helper_path}")

    node_bin = os.environ.get("READLIST_NODE_BIN", "node")
    command = [
        node_bin,
        helper_path,
        "--domain",
        args.audible_domain,
        "--profile-dir",
        args.browser_profile_dir,
        "--page-size",
        str(args.page_size),
        "--max-pages",
        str(args.max_pages),
    ]
    if args.browser_headless:
        command.append("--headless")
    for title in getattr(args, "_probe_titles", []):
        command.extend(["--probe-title", title])

    completed = subprocess.run(
        command,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "Node browser fetch failed. Ensure Node Playwright is installed globally "
            "(Arch: pacman -S playwright) and Chromium is installed via `playwright install chromium`."
        )

    try:
        return json.loads(completed.stdout.strip() or "[]")
    except json.JSONDecodeError as exc:
        raise RuntimeError("Node browser fetch returned invalid JSON payload.") from exc


def main():
    args = parse_args()
    readlist_path = os.path.expanduser(args.readlist)

    should_import = not args.no_import
    if args.fetch_audible_api and args.fetch_audible_browser:
        print("Use only one import mode: --fetch-audible-api or --fetch-audible-browser.", file=sys.stderr)
        return 2

    if should_import and not args.audible_html and not args.fetch_audible_api and not args.fetch_audible_browser:
        print(
            "Provide --audible-html, --fetch-audible-api, or --fetch-audible-browser (unless --no-import is set).",
            file=sys.stderr,
        )
        return 2

    if os.path.exists(readlist_path):
        with open(readlist_path, "r", encoding="utf-8") as readlist:
            lines = readlist.readlines()
        if not any(line.strip() for line in lines):
            lines = DEFAULT_READLIST.splitlines(keepends=True)
    else:
        lines = DEFAULT_READLIST.splitlines(keepends=True)

    lines = ensure_readlist_structure(lines)
    should_write = False

    if should_import:
        known_owned_before = collect_imported_owned_titles(lines) if args.sync else {}
        if args.sync and args.fetch_audible_browser:
            probe_titles = (
                collect_acquisition_titles(lines)
                + collect_checked_titles(lines)
                + collect_archive_titles(lines)
            )
            args._probe_titles = list(dict.fromkeys(probe_titles))
        else:
            args._probe_titles = []

        if args.fetch_audible_browser:
            try:
                fetched_items = normalize_fetched_items(fetch_titles_from_audible_browser(args))
            except Exception as exc:
                print(f"Audible browser import failed: {exc}", file=sys.stderr)
                return 1
            source_label = f"Audible Browser API ({args.audible_domain})"
        elif args.fetch_audible_api:
            try:
                fetched_items = normalize_fetched_items(fetch_titles_from_audible_api(args))
            except Exception as exc:
                print(f"Audible API import failed: {exc}", file=sys.stderr)
                return 1
            source_label = f"Audible API ({args.audible_domain})"
        else:
            source_path = os.path.expanduser(args.audible_html)
            if not os.path.exists(source_path):
                print(f"Audible HTML file not found: {source_path}", file=sys.stderr)
                return 1
            with open(source_path, "r", encoding="utf-8", errors="ignore") as source:
                content = source.read()
            fetched_items = normalize_fetched_items(
                [{"title": title, "author": None} for title in extract_titles_from_html(content)]
            )
            source_label = f"Audible HTML ({source_path})"

        titles = [item.title for item in fetched_items]

        fetched_map = {}
        fetched_match_map = {}
        fetched_metadata_match_map = {}
        for item in fetched_items:
            title = canonical_title(item.title)
            fetched_map[title.casefold()] = title
            match_key = title_match_key(title)
            fetched_match_map[match_key] = title
            fetched_metadata_match_map[match_key] = {
                "author": item.author,
                "series": item.series,
                "summary": item.summary,
            }

        known_owned_match_map = {
            title_match_key(title): title for title in known_owned_before.values()
        }
        newly_owned = []
        missing_now = []
        if args.sync:
            fetched_base = {}
            known_base = {}
            for title in fetched_match_map.values():
                key = base_title_match_key(title)
                if key:
                    fetched_base.setdefault(key, set()).add(title_match_key(title))
            for title in known_owned_match_map.values():
                key = base_title_match_key(title)
                if key:
                    known_base.setdefault(key, set()).add(title_match_key(title))

            def is_matched_in_known(fetch_key):
                if fetch_key in known_owned_match_map:
                    return True
                fetched_title = fetched_match_map.get(fetch_key, "")
                base = base_title_match_key(fetched_title)
                if not base:
                    return False
                return bool(known_base.get(base))

            def is_matched_in_fetched(known_key):
                if known_key in fetched_match_map:
                    return True
                known_title = known_owned_match_map.get(known_key, "")
                base = base_title_match_key(known_title)
                if not base:
                    return False
                return bool(fetched_base.get(base))

            newly_owned = sorted(
                [
                    fetched_match_map[key]
                    for key in fetched_match_map
                    if key and not is_matched_in_known(key)
                ],
                key=str.casefold,
            )
            missing_now = sorted(
                [
                    known_owned_match_map[key]
                    for key in known_owned_match_map
                    if key and not is_matched_in_fetched(key)
                ],
                key=str.casefold,
            )

        if args.dry_run:
            if args.sync:
                print(f"Sync dry-run from {source_label}")
                print(f"Fetched: {len(titles)}")
                print(f"Known owned before: {len(known_owned_before)}")
                print(f"Newly owned: {len(newly_owned)}")
                for title in newly_owned:
                    print(f"+ {title}")
                print(f"Missing now: {len(missing_now)}")
                for title in missing_now:
                    print(f"- {title}")
                return 0

            print(f"Detected {len(titles)} title(s).")
            for title in titles:
                print(f"- {title}")
            return 0

        imported_count = 0
        if not args.sync:
            lines, imported_count = insert_imported_titles(lines, titles)
            print(f"Imported {imported_count} title(s) from {source_label}.")
            should_write = should_write or imported_count > 0

        if args.sync:
            lines, enriched_count = enrich_missing_metadata(lines, fetched_metadata_match_map)
            if enriched_count:
                print(f"Enriched metadata on {enriched_count} title(s).")
            should_write = should_write or enriched_count > 0

        if args.sync:
            sync_lines = build_sync_section_lines(
                sync_date=date.today().isoformat(),
                fetched_count=len(titles),
                known_count=len(known_owned_before),
                new_titles=newly_owned,
                missing_titles=missing_now,
            )
            lines, sync_changed = upsert_sync_section(lines, sync_lines)
            should_write = should_write or sync_changed
            print(
                f"Sync summary: {len(newly_owned)} newly owned, "
                f"{len(missing_now)} missing from current pull."
            )

    if args.archive_finished:
        lines, archived_count = archive_finished_items(lines, args.finished_date)
        print(f"Archived {archived_count} finished item(s).")
        should_write = should_write or archived_count > 0

    if should_write:
        with open(readlist_path, "w", encoding="utf-8") as readlist:
            readlist.writelines(lines)
        print(f"Updated readlist: {readlist_path}")
    else:
        print("No readlist changes.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
