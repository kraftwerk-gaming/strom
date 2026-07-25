#!/usr/bin/env python3
"""Generate the README games table, per-game metadata.json build keys, and the
web/index.html checker dataset from flake metadata.

Each game's `cids`, `description` and `runtime` are pure projections of its
`default.nix` (flake eval via generate-readme.nix). They are written into
`games/<slug>/metadata.json` (merged over any hand-authored keys, which are left
untouched) so the build and the fetch script can read them without a flake eval,
and baked into `web/index.html` so the standalone IPFS checker is self-contained.
There is no `web/games.json`.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

BEGIN_MARKER = "<!-- BEGIN GENERATED GAMES -->"
END_MARKER = "<!-- END GENERATED GAMES -->"
DATA_BEGIN = "<!-- BEGIN GENERATED GAMES DATA -->"
DATA_END = "<!-- END GENERATED GAMES DATA -->"

SCRIPT_DIR = Path(__file__).parent
NIX_FILE = SCRIPT_DIR / "generate-readme.nix"
ROOT = SCRIPT_DIR.parent
README = ROOT / "README.md"
GAMES_DIR = ROOT / "games"
INDEX_HTML = ROOT / "web" / "index.html"


def get_metadata() -> dict[str, dict[str, str | list[str] | None]]:
    proc = subprocess.run(
        ["nix", "eval", "--json", "--file", str(NIX_FILE)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        sys.exit(1)
    return json.loads(proc.stdout)


def filter_games(meta: dict) -> dict:
    return {slug: m for slug, m in meta.items() if (GAMES_DIR / slug).is_dir()}


def render_table(games: dict) -> str:
    lines: list[str] = []
    lines.append("| | Game | Runtime | Run |")
    lines.append("| --- | --- | --- | --- |")

    for slug in sorted(games):
        m = games[slug]
        desc = m.get("description") or slug
        # Strip trailing parentheticals that describe the runtime
        # environment ("(via Proton ...)", "(native Linux)", etc.). The
        # runtime column already conveys this.
        desc = re.sub(r"\s*\([^()]*\)\s*$", "", desc).strip()
        runtime = m.get("runtime") or "unknown"

        lutris_url = f"https://lutris.net/games/{slug}/"
        banner_url = f"https://lutris.net/games/banner/{slug}.jpg"
        banner_cell = (
            f'<a href="{lutris_url}">'
            f'<img src="{banner_url}" height="40" alt="{slug}">'
            f"</a>"
        )
        name_cell = f"[{desc}]({lutris_url})"
        run_cell = f"`nix run .#{slug}`"

        lines.append(f"| {banner_cell} | {name_cell} | `{runtime}` | {run_cell} |")

    lines.append("")
    lines.append(f"_{len(games)} games_")
    return "\n".join(lines)


def build_values(m: dict) -> dict:
    """The flake-projected build keys generate-readme.py owns in metadata.json."""
    return {
        "cids": m.get("cids") or [],
        "description": m.get("description"),
        "runtime": m.get("runtime") or "unknown",
    }


def replace_between(text: str, begin: str, end: str, body: str, where: Path) -> str:
    b = text.find(begin)
    e = text.find(end)
    if b == -1 or e == -1 or e < b:
        sys.stderr.write(
            f"Error: markers not found in {where}\n"
            f"  Expected: {begin}\n"
            f"  And:      {end}\n"
        )
        sys.exit(1)
    return text[: b + len(begin)] + body + text[e:]


def update_readme(generated: str) -> bool:
    content = README.read_text()
    new = replace_between(
        content, BEGIN_MARKER, END_MARKER, "\n\n" + generated + "\n\n", README
    )
    if new == content:
        return False
    README.write_text(new)
    return True


def update_metadata_files(games: dict) -> list[str]:
    """Merge each game's build keys into games/<slug>/metadata.json, preserving
    hand-authored keys. Returns the slugs whose file changed."""
    changed: list[str] = []
    for slug, m in games.items():
        path = GAMES_DIR / slug / "metadata.json"
        existing: dict = {}
        if path.exists():
            try:
                existing = json.loads(path.read_text())
            except json.JSONDecodeError:
                existing = {}
        merged = dict(existing)
        merged.update(build_values(m))
        payload = json.dumps(merged, indent=2, sort_keys=True) + "\n"
        if not path.exists() or path.read_text() != payload:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(payload)
            changed.append(slug)
    return changed


def update_index_html(games: dict) -> bool:
    data = {slug: build_values(m) for slug, m in games.items()}
    body = (
        '\n<script type="application/json" id="games-data">\n'
        + json.dumps(data, indent=2, sort_keys=True)
        + "\n</script>\n"
    )
    content = INDEX_HTML.read_text()
    new = replace_between(content, DATA_BEGIN, DATA_END, body, INDEX_HTML)
    if new == content:
        return False
    INDEX_HTML.write_text(new)
    return True


def main() -> None:
    if not README.exists():
        sys.stderr.write(f"Error: {README} not found\n")
        sys.exit(1)

    meta = get_metadata()
    games = filter_games(meta)

    print(
        f"Updated {README}"
        if update_readme(render_table(games))
        else "No README changes"
    )

    changed = update_metadata_files(games)
    print(
        f"Updated {len(changed)} metadata.json file(s)"
        if changed
        else "No metadata.json changes"
    )

    print(
        f"Updated {INDEX_HTML}" if update_index_html(games) else "No index.html changes"
    )


if __name__ == "__main__":
    main()
