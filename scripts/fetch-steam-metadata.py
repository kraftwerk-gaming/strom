#!/usr/bin/env python3
"""Enrich the strom catalog with Steam store metadata.

Reads the generated slug list from ``web/games.json``, matches each game to a
Steam appid (auto fuzzy-match by name, with manual fixups in
``scripts/steam-overrides.json``), fetches the Steam ``appdetails`` API for
screenshots / descriptions / genres / release year / developers, and writes
``web/catalog.json`` consumed by the web GUI.

Games without a Steam match fall back to the lutris banner (the same URL the
couch launcher and README use), so every game still renders a tile.

Raw API responses are cached under ``web/.steam-cache/`` (gitignored) so reruns
are cheap and can run fully offline with ``--offline``.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).parent
ROOT = SCRIPT_DIR.parent
GAMES_JSON = ROOT / "web" / "games.json"
CATALOG_JSON = ROOT / "web" / "catalog.json"
OVERRIDES_JSON = SCRIPT_DIR / "steam-overrides.json"
CACHE_DIR = ROOT / "web" / ".steam-cache"

STORESEARCH_URL = "https://store.steampowered.com/api/storesearch/"
APPDETAILS_URL = "https://store.steampowered.com/api/appdetails"
LUTRIS_BANNER = "https://lutris.net/games/banner/{slug}.jpg"
LUTRIS_PAGE = "https://lutris.net/games/{slug}/"

USER_AGENT = "strom-catalog/1 (+https://github.com/kraftwerk-gaming/strom)"
# Steam store API is rate limited (~200 requests / 5 min). Stay well under it;
# cached responses skip the sleep entirely.
THROTTLE_SECONDS = 1.5
MAX_SCREENSHOTS = 8

# Edition / packaging words that appear in strom descriptions but not in the
# canonical Steam store name. Stripping them improves auto-matching.
EDITION_NOISE = re.compile(
    r"\b("
    r"complete(\s+(collection|edition|tale))?|"
    r"gold(\s+edition)?|"
    r"enhanced\s+edition|"
    r"definitive\s+edition|"
    r"deluxe(\s+edition)?|"
    r"game\s+of\s+the\s+year(\s+edition)?|goty(\s+edition)?|"
    r"remastered|anniversary(\s+edition)?|"
    r"the\s+complete\s+tale|directors?\s+cut|"
    r"\+\s*\d*\s*dlc"
    r")\b",
    re.IGNORECASE,
)

TAG_RE = re.compile(r"<[^>]+>")

# Search hits whose name contains these are never the base game; reject them
# when falling back to the top (non-exact) search result.
BAD_HIT = re.compile(
    r"soundtrack|\bost\b|\bdlc\b|demo|trailer|artbook|bonus|season\s+pass",
    re.IGNORECASE,
)


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


def http_get(url: str, *, offline: bool) -> bytes | None:
    if offline:
        return None
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data: bytes = resp.read()
            return data
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        log(f"  ! fetch failed {url}: {exc}")
        return None


def strip_html(text: str) -> str:
    """Turn Steam's HTML description into readable plain text."""
    text = re.sub(r"<\s*br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</\s*(p|li|h[1-9])\s*>", "\n", text, flags=re.IGNORECASE)
    text = TAG_RE.sub("", text)
    text = html.unescape(text)
    # Collapse runs of blank lines / trailing whitespace.
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def normalize(name: str) -> str:
    """Lowercase and drop everything but alphanumerics for fuzzy comparison."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


def search_name(slug: str, description: str | None) -> str:
    """Best human name guess for a game: the description minus the trailing
    parenthetical (which describes the runtime), falling back to the slug."""
    name = description or slug.replace("-", " ")
    name = re.sub(r"\s*\([^()]*\)\s*$", "", name).strip()
    return name or slug.replace("-", " ")


def match_candidates(name: str) -> list[str]:
    """Progressively trimmed name variants to try against the Steam app list."""
    variants = [name]
    stripped = EDITION_NOISE.sub("", name)
    stripped = re.sub(r"\s{2,}", " ", stripped).strip(" :-+")
    if stripped and stripped != name:
        variants.append(stripped)
    # Drop a trailing " - subtitle" / " : subtitle" as a last resort.
    base = re.split(r"\s+[-:]\s+", name)[0].strip()
    if base and base not in variants:
        variants.append(base)
    return variants


def storesearch(term: str, offline: bool) -> list[dict[str, Any]]:
    """Query the Steam store search API for a term, returning ranked app hits.
    Cached per normalized term so reruns are cheap and offline-capable."""
    cache = CACHE_DIR / f"search-{normalize(term) or 'empty'}.json"
    raw: bytes | None
    if cache.exists():
        raw = cache.read_bytes()
    else:
        query = urllib.parse.urlencode({"term": term, "cc": "us", "l": "english"})
        raw = http_get(f"{STORESEARCH_URL}?{query}", offline=offline)
        if raw is None:
            return []
        cache.write_bytes(raw)
        time.sleep(THROTTLE_SECONDS)
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return []
    items = payload.get("items", [])
    return [it for it in items if it.get("type") == "app" and it.get("id")]


def resolve_appid(
    slug: str,
    name: str,
    overrides: dict[str, Any],
    offline: bool,
) -> int | None:
    if slug in overrides:
        # Explicit fixup wins, including an explicit null = "skip Steam".
        value = overrides[slug]
        return int(value) if isinstance(value, int) else None

    for variant in match_candidates(name):
        items = storesearch(variant, offline)
        if not items:
            continue
        target = normalize(variant)
        # Prefer an exact normalized-name match anywhere in the results.
        for it in items:
            if normalize(it["name"]) == target:
                return int(it["id"])
        # Otherwise accept the top hit only when it is a strong prefix match
        # and is not an obvious soundtrack / DLC / demo entry.
        top = items[0]
        top_norm = normalize(top["name"])
        if not BAD_HIT.search(top["name"]) and (
            top_norm.startswith(target) or target.startswith(top_norm)
        ):
            return int(top["id"])
    return None


def fetch_appdetails(appid: int, offline: bool) -> dict[str, Any] | None:
    cache = CACHE_DIR / f"app-{appid}.json"
    raw: bytes | None
    if cache.exists():
        raw = cache.read_bytes()
    else:
        query = urllib.parse.urlencode({"appids": appid, "l": "english"})
        raw = http_get(f"{APPDETAILS_URL}?{query}", offline=offline)
        if raw is None:
            return None
        cache.write_bytes(raw)
        time.sleep(THROTTLE_SECONDS)
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None
    entry = payload.get(str(appid))
    if not entry or not entry.get("success"):
        return None
    data = entry.get("data")
    return data if isinstance(data, dict) else None


def parse_year(release: dict[str, Any]) -> int | None:
    match = re.search(r"\b(19|20)\d{2}\b", release.get("date", "") or "")
    return int(match.group()) if match else None


def build_entry(
    slug: str,
    games: dict[str, Any],
    appid: int | None,
    details: dict[str, Any] | None,
) -> dict[str, Any]:
    meta = games[slug]
    runtime = meta.get("runtime") or "unknown"
    fallback_name = search_name(slug, meta.get("description"))

    if details:
        screenshots = [
            s["path_full"] for s in details.get("screenshots", []) if s.get("path_full")
        ][:MAX_SCREENSHOTS]
        long_html = details.get("detailed_description") or details.get(
            "about_the_game", ""
        )
        return {
            "name": details.get("name") or fallback_name,
            "runtime": runtime,
            "short": (details.get("short_description") or "").strip(),
            "long": strip_html(long_html),
            "genres": [g["description"] for g in details.get("genres", [])],
            # Steam "categories" carry the player-mode features the GUI filters
            # on (Single-player, Co-op, Remote Play Together, ...).
            "tags": [
                c["description"]
                for c in details.get("categories", [])
                if c.get("description")
            ],
            "year": parse_year(details.get("release_date", {})),
            "developers": details.get("developers", []),
            "hero": details.get("header_image") or LUTRIS_BANNER.format(slug=slug),
            "screenshots": screenshots,
            "lutris": LUTRIS_PAGE.format(slug=slug),
            "steam_appid": appid,
        }

    # Fallback: no Steam data. Use the strom description and lutris banner so
    # the game still renders a tile and a (sparse) detail view.
    return {
        "name": fallback_name,
        "runtime": runtime,
        "short": (meta.get("description") or "").strip(),
        "long": "",
        "genres": [],
        "tags": [],
        "year": None,
        "developers": [],
        "hero": LUTRIS_BANNER.format(slug=slug),
        "screenshots": [],
        "lutris": LUTRIS_PAGE.format(slug=slug),
        "steam_appid": None,
    }


def write_catalog(catalog: dict[str, Any]) -> bool:
    payload = json.dumps(catalog, indent=2, sort_keys=True) + "\n"
    CATALOG_JSON.parent.mkdir(parents=True, exist_ok=True)
    if CATALOG_JSON.exists() and CATALOG_JSON.read_text() == payload:
        return False
    CATALOG_JSON.write_text(payload)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--offline",
        action="store_true",
        help="use only the local cache; never hit the network",
    )
    parser.add_argument(
        "slugs",
        nargs="*",
        help="limit enrichment to these slugs (default: all in games.json)",
    )
    args = parser.parse_args()

    if not GAMES_JSON.exists():
        log(f"Error: {GAMES_JSON} not found; run generate-readme.py first")
        return 1

    games: dict[str, Any] = json.loads(GAMES_JSON.read_text())
    overrides: dict[str, Any] = (
        json.loads(OVERRIDES_JSON.read_text()) if OVERRIDES_JSON.exists() else {}
    )
    overrides = {k: v for k, v in overrides.items() if not k.startswith("_")}

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    slugs = sorted(args.slugs or games)
    catalog: dict[str, Any] = {}
    matched = 0
    for i, slug in enumerate(slugs, 1):
        if slug not in games:
            log(f"  ? unknown slug {slug!r}, skipping")
            continue
        name = search_name(slug, games[slug].get("description"))
        appid = resolve_appid(slug, name, overrides, args.offline)
        details = fetch_appdetails(appid, args.offline) if appid else None
        if details:
            matched += 1
        catalog[slug] = build_entry(slug, games, appid, details)
        tag = f"steam:{appid}" if details else "fallback"
        log(f"[{i}/{len(slugs)}] {slug} -> {tag}")

    log(f"\nMatched {matched}/{len(slugs)} games to Steam.")
    if write_catalog(catalog):
        log(f"Updated {CATALOG_JSON}")
    else:
        log(f"No changes to {CATALOG_JSON}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
