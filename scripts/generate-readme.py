#!/usr/bin/env python3
"""Generate the games table in README.md and web/games.json from flake metadata."""

import json
import re
import subprocess
import sys
from pathlib import Path

BEGIN_MARKER = "<!-- BEGIN GENERATED GAMES -->"
END_MARKER = "<!-- END GENERATED GAMES -->"

SCRIPT_DIR = Path(__file__).parent
NIX_FILE = SCRIPT_DIR / "generate-readme.nix"
ROOT = SCRIPT_DIR.parent
README = ROOT / "README.md"
GAMES_DIR = ROOT / "games"
GAMES_JSON = ROOT / "web" / "games.json"


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


def update_readme(generated: str) -> bool:
    content = README.read_text()

    begin = content.find(BEGIN_MARKER)
    end = content.find(END_MARKER)
    if begin == -1 or end == -1 or end < begin:
        sys.stderr.write(
            f"Error: markers not found in {README}\n"
            f"  Expected: {BEGIN_MARKER}\n"
            f"  And:      {END_MARKER}\n"
        )
        sys.exit(1)

    new = (
        content[: begin + len(BEGIN_MARKER)]
        + "\n\n"
        + generated
        + "\n\n"
        + content[end:]
    )

    if new == content:
        return False
    README.write_text(new)
    return True


def update_games_json(games: dict) -> bool:
    payload = json.dumps(games, indent=2, sort_keys=True) + "\n"
    GAMES_JSON.parent.mkdir(parents=True, exist_ok=True)
    if GAMES_JSON.exists() and GAMES_JSON.read_text() == payload:
        return False
    GAMES_JSON.write_text(payload)
    return True


def main() -> None:
    if not README.exists():
        sys.stderr.write(f"Error: {README} not found\n")
        sys.exit(1)

    meta = get_metadata()
    games = filter_games(meta)

    if update_readme(render_table(games)):
        print(f"Updated {README}")
    else:
        print(f"No changes to {README}")

    if update_games_json(games):
        print(f"Updated {GAMES_JSON}")
    else:
        print(f"No changes to {GAMES_JSON}")


if __name__ == "__main__":
    main()
