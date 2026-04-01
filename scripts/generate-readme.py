#!/usr/bin/env python3
"""Generate the games table in README.md from flake metadata."""

import json
import subprocess
import sys
from pathlib import Path

BEGIN_MARKER = "<!-- BEGIN GENERATED GAMES -->"
END_MARKER = "<!-- END GENERATED GAMES -->"

SCRIPT_DIR = Path(__file__).parent
NIX_FILE = SCRIPT_DIR / "generate-readme.nix"
README = SCRIPT_DIR.parent / "README.md"
GAMES_DIR = SCRIPT_DIR.parent / "games"


def get_metadata() -> dict[str, dict[str, str | None]]:
    proc = subprocess.run(
        ["nix", "eval", "--json", "--file", str(NIX_FILE)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        sys.exit(1)
    return json.loads(proc.stdout)


def render(meta: dict[str, dict[str, str | None]]) -> str:
    lines: list[str] = []
    lines.append("| | Game | Runtime | Run |")
    lines.append("| --- | --- | --- | --- |")

    for slug in sorted(meta):
        m = meta[slug]
        desc = m.get("description") or slug
        runtime = m.get("runtime") or "unknown"

        lutris_url = f"https://lutris.net/games/{slug}/"
        banner_url = f"https://lutris.net/games/banner/{slug}.jpg"
        banner_cell = (
            f'<a href="{lutris_url}">'
            f'<img src="{banner_url}" height="40" alt="{slug}">'
            f"</a>"
        )
        name_cell = f"[{desc}]({lutris_url})"
        run_cell = f"`nix run github:kraftwerk-gaming/strom#{slug}`"

        lines.append(f"| {banner_cell} | {name_cell} | `{runtime}` | {run_cell} |")

    lines.append("")
    lines.append(f"_{len(meta)} games_")
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


def main() -> None:
    if not README.exists():
        sys.stderr.write(f"Error: {README} not found\n")
        sys.exit(1)

    meta = get_metadata()
    generated = render(meta)

    if update_readme(generated):
        print(f"Updated {README}")
    else:
        print(f"No changes to {README}")


if __name__ == "__main__":
    main()
