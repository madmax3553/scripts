#!/home/groot/.local/share/journal-venv/bin/python3
import argparse
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import Optional

from simplejustwatchapi import providers, search


WATCHLIST_PATH = os.path.expanduser("~/journal/notes/watchlist.md")
ENTRY_PATTERN = re.compile(
    r'^(\s*-\s+\[([ xX])\]\s+\*\*([^*]+)\*\*(?:\s+\(([^)]+)\))?)(.*)$'
)
SERVICE_ENTRY_PATTERN = re.compile(r'^\s*-\s+\[([ xX])\]\s+(.+?)\s*$')
JUSTWATCH_LINK_PATTERN = re.compile(r'\s*\[JustWatch\]\([^)]+\)\s*$')
SERVICES_HEADING = "## Services"
BACK_TO_DASHBOARD = "*Back to [[index|Dashboard]]*"


@dataclass(frozen=True)
class WatchItem:
    idx: int
    checkbox: str
    clean_line: str
    title: str
    search_title: str
    info: Optional[str]
    old_suffix: str

    @property
    def checked(self) -> bool:
        return self.checkbox.lower() == "x"


@dataclass(frozen=True)
class WatchResult:
    idx: int
    source_line: str
    diary_line: str
    old_status_key: str
    new_status_key: str
    changed: bool
    became_available: bool
    checked: bool
    services: tuple[str, ...]


def clean_provider_name(name):
    name_map = {
        "AcornTV": "Acorn TV",
        "Acorn TV Apple TV": "Acorn TV",
        "AMC Plus": "AMC+",
        "Amazon Prime Video": "Prime Video",
        "Amazon Prime Video with Ads": "Prime Video",
        "Amazon Video": "Amazon Store",
        "Apple TV Store": "Apple TV",
        "Britbox": "BritBox",
        "Discovery +": "Discovery+",
        "Google Play Movies": "Google Play",
        "HiDive": "Hidive",
        "MLB.TV": "MLB TV",
        "Netflix Standard with Ads": "Netflix",
        "Netflix (Ads)": "Netflix",
        "Paramount Plus": "Paramount+",
        "Paramount Plus Basic with Ads": "Paramount+",
        "Paramount Plus Premium": "Paramount+",
        "Paramount+ (Ads)": "Paramount+",
        "Prime Video (Ads)": "Prime Video",
        "tvo": "TVO",
        "Tubi TV": "Tubi",
    }
    return name_map.get(name.strip(), name.strip())


def normalize_provider_name(name):
    base = clean_provider_name(name)
    for channel_suffix in [
        " Amazon Channel",
        " Apple TV Channel",
        " Apple Tv channel",
        " Roku Premium Channel",
        " Premium Channel",
    ]:
        lower_base = base.lower()
        lower_suffix = channel_suffix.lower()
        if lower_suffix in lower_base:
            base = base[:lower_base.index(lower_suffix)].strip()
    return clean_provider_name(base)


def clean_providers(providers):
    cleaned = []
    for provider in providers:
        provider = normalize_provider_name(provider)
        if provider:
            cleaned.append(provider)

    seen = set()
    result = []
    for provider in cleaned:
        if provider not in seen:
            seen.add(provider)
            result.append(provider)

    final_result = []
    for provider in result:
        if provider.endswith(" (Ads)"):
            base_provider = provider[:-6]
            if base_provider in result:
                continue
        final_result.append(provider)

    return final_result


def parse_args():
    parser = argparse.ArgumentParser(
        description="Update watchlist JustWatch statuses and optionally append diary changes."
    )
    parser.add_argument(
        "--watchlist",
        default=WATCHLIST_PATH,
        help=f"Watchlist markdown file to update. Default: {WATCHLIST_PATH}",
    )
    parser.add_argument(
        "--append-diary",
        metavar="PATH",
        help="Append newly available unchecked items to this diary file.",
    )
    return parser.parse_args()


def parse_config(content):
    country = "CA"
    legacy_services = []
    for line in content.splitlines():
        country_match = re.search(r'\*\*Country:\*\*\s*(\w{2})', line, re.IGNORECASE)
        if country_match:
            country = country_match.group(1).upper()

        services_match = re.search(
            r'\*\*(?:My Services|Services Owned):\*\*\s*([^\n]+)', line, re.IGNORECASE
        )
        if services_match:
            legacy_services = [
                normalize_provider_name(service)
                for service in services_match.group(1).split(",")
            ]

    checked_services, known_services = parse_service_section(content)
    if checked_services:
        my_services = sorted(checked_services, key=str.casefold)
    else:
        my_services = legacy_services
        known_services.update(legacy_services)

    return country, my_services, known_services


def parse_service_section(content):
    checked_services = set()
    known_services = set()
    in_services = False

    for line in content.splitlines():
        if line.strip() == SERVICES_HEADING:
            in_services = True
            continue

        if in_services and line.startswith("## "):
            in_services = False

        if not in_services:
            continue

        match = SERVICE_ENTRY_PATTERN.match(line)
        if not match:
            continue

        checkbox, service = match.groups()
        service = normalize_provider_name(service)
        if not service:
            continue

        known_services.add(service)
        if checkbox.lower() == "x":
            checked_services.add(service)

    return checked_services, known_services


def parse_items(lines):
    items = []
    for idx, line in enumerate(lines):
        match = ENTRY_PATTERN.match(line.rstrip("\n"))
        if not match:
            continue

        full_prefix, checkbox, title, info, suffix = match.groups()
        title = title.strip()
        info = info.strip() if info else None
        search_title = title.split("/")[0].strip() if "/" in title else title
        items.append(
            WatchItem(
                idx=idx,
                checkbox=checkbox,
                clean_line=full_prefix.rstrip(),
                title=title,
                search_title=search_title,
                info=info,
                old_suffix=suffix.strip(),
            )
        )
    return items


def status_key(text):
    text = text.strip()
    text = re.sub(r'^[—-]\s*', '', text)
    text = JUSTWATCH_LINK_PATTERN.sub('', text).strip()
    return re.sub(r'\s+', ' ', text)


def is_actionable_status(text):
    text = status_key(text)
    return text.startswith("🟢") or text.startswith("🟡")


def display_title(item):
    if item.info:
        return f"**{item.title}** ({item.info})"
    return f"**{item.title}**"


def build_result(item, status, url, actionable, services=None):
    link = f" [JustWatch]({url})" if url else ""
    source_line = f"{item.clean_line} — {status}{link}"
    diary_line = f"- {display_title(item)} - {status}{link}"
    old_status_key = status_key(item.old_suffix)
    new_status_key = status_key(status)
    services = tuple(sorted(services or [], key=str.casefold))

    return WatchResult(
        idx=item.idx,
        source_line=source_line,
        diary_line=diary_line,
        old_status_key=old_status_key,
        new_status_key=new_status_key,
        changed=old_status_key != new_status_key,
        became_available=not is_actionable_status(old_status_key) and actionable,
        checked=item.checked,
        services=services,
    )


def query_item(item, country, my_services):
    try:
        results = search(item.search_title, country=country, language="en", count=5)
        if not results:
            return build_result(item, "🔴 No results on JustWatch", None, actionable=False)

        best_match = None
        is_tv = item.info == "TV Series"
        target_year = int(item.info) if item.info and item.info.isdigit() else None

        for result in results:
            year_match = True
            if target_year and getattr(result, 'release_year', None):
                year_match = abs(result.release_year - target_year) <= 1

            type_match = True
            if is_tv:
                type_match = result.object_type == "SHOW"
            elif target_year:
                type_match = result.object_type == "MOVIE"

            if year_match and type_match:
                best_match = result
                break

        if not best_match:
            best_match = results[0]

        streams = []
        rent_buys = []
        seen_providers = set()

        for offer in getattr(best_match, 'offers', []) or []:
            package = getattr(offer, 'package', None)
            provider = clean_provider_name(getattr(package, 'name', "Unknown"))
            monetization = getattr(offer, 'monetization_type', "").upper()

            provider_key = (provider, monetization)
            if provider_key in seen_providers:
                continue
            seen_providers.add(provider_key)

            if monetization in ["FLATRATE", "FREE", "ADS"]:
                streams.append(provider)
            elif monetization in ["RENT", "BUY"]:
                rent_buys.append(provider)

        streams = clean_providers(streams)
        rent_buys = clean_providers(rent_buys)
        available_services = clean_providers(streams + rent_buys)

        owned_streams = []
        other_streams = []
        for stream in streams:
            is_owned = any(
                owned.lower() in stream.lower() or stream.lower() in owned.lower()
                for owned in my_services
            )
            if is_owned:
                owned_streams.append(f"**{stream}**")
            else:
                other_streams.append(stream)

        if owned_streams:
            status = f"🟢 Stream: {', '.join(owned_streams)}"
            actionable = True
        elif other_streams:
            status = f"🔴 Not on your services (Available on: {', '.join(other_streams)})"
            actionable = False
        elif rent_buys:
            status = f"🟡 Rent/Buy: {', '.join(rent_buys)}"
            actionable = True
        else:
            status = "🔴 Not streaming"
            actionable = False

        url = getattr(best_match, 'url', None) or f'https://www.justwatch.com/{country.lower()}'
        return build_result(item, status, url, actionable=actionable, services=available_services)
    except Exception as exc:
        return build_result(item, f"⚠️ Error: {exc}", None, actionable=False, services=[])


def fetch_provider_catalog(country):
    try:
        catalog = providers(country)
    except Exception as exc:
        print(f"Provider catalog refresh failed: {exc}", file=sys.stderr)
        return set()

    return set(clean_providers(getattr(provider, "name", "") for provider in catalog))


def split_footer(lines):
    for idx in range(len(lines) - 1, -1, -1):
        if lines[idx].strip() != BACK_TO_DASHBOARD:
            continue

        footer_start = idx
        if idx >= 2 and lines[idx - 1].strip() == "" and lines[idx - 2].strip() == "---":
            footer_start = idx - 2
        return lines[:footer_start], lines[footer_start:]

    return lines, []


def strip_service_config(lines):
    result = []
    in_services = False

    for line in lines:
        if line.strip() == SERVICES_HEADING:
            in_services = True
            while result and result[-1].strip() in ["", "---"]:
                result.pop()
            continue

        if in_services:
            if line.startswith("## "):
                in_services = False
            else:
                continue

        if re.match(r'\s*\*\s+\*\*(?:My Services|Services Owned):\*\*', line, re.IGNORECASE):
            continue

        result.append(line)

    return result


def render_service_section(checked_services, known_services):
    lines = [
        "---\n",
        "\n",
        f"{SERVICES_HEADING}\n",
        "\n",
    ]

    for service in sorted(known_services, key=str.casefold):
        checkbox = "x" if service in checked_services else " "
        lines.append(f"- [{checkbox}] {service}\n")

    return lines


def update_service_config(lines, checked_services, known_services):
    body, footer = split_footer(lines)
    body = strip_service_config(body)

    while body and body[-1].strip() in ["", "---"]:
        body.pop()

    if body:
        body.append("\n")

    body.extend(render_service_section(checked_services, known_services))

    if footer:
        body.append("\n")
        body.extend(footer)

    return body


def append_diary_changes(target_file, country, my_services, results):
    changes = [
        result
        for result in results
        if not result.checked and result.changed and result.became_available
    ]
    if not changes:
        print("No unchecked watchlist items became available for diary.")
        return

    output_lines = [
        "",
        f"## Watchlist Availability Changes (JustWatch {country})",
        f"*Checked on-boot via JustWatch. Owned services: {', '.join(my_services)}*",
        "",
    ]
    output_lines.extend(result.diary_line for result in changes)
    output_lines.append("")

    with open(target_file, "a", encoding="utf-8") as diary:
        diary.write("\n".join(output_lines))

    print(f"Appended {len(changes)} watchlist availability change(s) to {target_file}.")


def main():
    args = parse_args()
    watchlist_path = os.path.expanduser(args.watchlist)

    if not os.path.exists(watchlist_path):
        print(f"Watchlist file not found at {watchlist_path}")
        sys.exit(1)

    with open(watchlist_path, "r", encoding="utf-8") as watchlist:
        lines = watchlist.readlines()

    content = "".join(lines)
    country, my_services, known_services = parse_config(content)
    checked_services = set(my_services)
    initial_known_services = set(known_services)
    items = parse_items(lines)

    if not items:
        print("No items to update.")
        return

    print(f"Querying JustWatch ({country}) for {len(items)} watchlist items...")
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda item: query_item(item, country, my_services), items))

    for result in results:
        lines[result.idx] = f"{result.source_line}\n"

    provider_catalog = fetch_provider_catalog(country)
    discovered_services = set()
    for result in results:
        discovered_services.update(result.services)
    known_services.update(provider_catalog)
    known_services.update(discovered_services)
    known_services.update(checked_services)
    lines = update_service_config(lines, checked_services, known_services)

    with open(watchlist_path, "w", encoding="utf-8") as watchlist:
        watchlist.writelines(lines)

    changed_count = sum(1 for result in results if result.changed)
    new_service_count = len((provider_catalog | discovered_services) - initial_known_services)
    print(
        f"Watchlist updated successfully "
        f"({changed_count} status change(s), {new_service_count} new service(s))."
    )

    if args.append_diary:
        append_diary_changes(os.path.expanduser(args.append_diary), country, my_services, results)


if __name__ == "__main__":
    main()
