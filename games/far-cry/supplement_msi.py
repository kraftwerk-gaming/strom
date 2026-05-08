#!/usr/bin/env python3
"""Supplement an msiextract output tree with files that msitools dropped.

The Far Cry installer ships Data2.cab + Data21.cab as a single multi-volume
MSZip cabinet. msitools' built-in cab reader fails on the volume boundary
with "Invalid folder index" and silently aborts that folder, leaving ~22
files unextracted -- including FCData/Music.pak, FCData/Sounds.pak,
FCData/Objects.pak, and Languages/Movies/DemoLoops/CryTek.bik. Without
these the engine null-derefs during startup ("CRITICAL ERROR" right after
`Loading DevMode.lua: Ok!`) and there is no menu music.

This script:
  1. Reads File / Component / Directory / Media from the original FC32.msi.
  2. Re-extracts every named CAB with 7z (which handles the multi-volume
     continuation cleanly) into a flat staging directory; cab member names
     match the MSI File.File primary key, so we can find each payload by
     its GUID-ish key.
  3. For every File row whose CAB lives on a numbered Disk (i.e. not the
     loose Disk 11 entries), computes its on-disk path beneath the game's
     INSTALLDIR by walking Directory parents, and copies the payload from
     the staging dir into the game tree if it is not already there.

Loose Disk 11 entries (Cabinet="") are skipped here -- the caller pulls
the small handful that matter (FarCry.exe, the .bik movies) out of the ISO
directly with `7z x`.
"""

from __future__ import annotations

import csv
import shutil
import subprocess
import sys
from pathlib import Path


def parse_idt(path: Path) -> list[dict[str, str]]:
    """Parse an `msiinfo export`d table.

    The first three lines are column names, column types, and the
    table-name marker; everything after that is data.
    """
    with path.open(encoding="utf-8", errors="replace") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)
        next(reader)  # types
        next(reader)  # table-name marker
        return [dict(zip(header, row)) for row in reader if row]


def real_dirname(default_dir: str) -> str:
    """Translate an MSI Directory.DefaultDir field to the on-disk folder name.

    DefaultDir uses "short|long" for long names, and a trailing ":." marks
    a path component whose source-side short name is "." (i.e. the source
    media keeps the file at the parent level even though the install tree
    nests it under this directory). msitools encodes that into directory
    names; we strip it because the buildScript flattens those anyway.
    """
    s = default_dir
    if "|" in s:
        s = s.split("|", 1)[1]
    while s.endswith(":."):
        s = s[:-2]
    if s.endswith(":"):
        s = s[:-1]
    return s


def build_dir_paths(dirs: list[dict[str, str]]) -> dict[str, list[str]]:
    """Resolve each Directory row to its components below TARGETDIR."""
    by_name = {d["Directory"]: d for d in dirs}
    out: dict[str, list[str]] = {}

    def resolve(name: str) -> list[str]:
        if name in out:
            return out[name]
        if name == "TARGETDIR":
            out[name] = []
            return []
        row = by_name[name]
        parent = row["Directory_Parent"]
        parent_path = resolve(parent) if parent else []
        own = real_dirname(row["DefaultDir"])
        if own in (".", ""):
            out[name] = list(parent_path)
        else:
            out[name] = list(parent_path) + [own]
        return out[name]

    for d in by_name:
        resolve(d)
    return out


def main() -> int:
    iso_dir = Path(sys.argv[1])  # holds the named .cab files (and FC32.msi)
    out_root = Path(sys.argv[2])  # the per-build $out for far-cry-data
    install_subpath = Path(sys.argv[3])  # e.g. "Ubisoft/Crytek/Far Cry"
    msi_path = Path(sys.argv[4])  # path to FC32.msi

    # Dump the four tables we need to a temp dir (msiinfo writes to stdout).
    tmp = out_root.parent / "_msi_tables"
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)
    for tbl in ("File", "Component", "Directory", "Media"):
        with (tmp / f"{tbl}.idt").open("wb") as f:
            subprocess.run(
                ["msiinfo", "export", str(msi_path), tbl],
                check=True,
                stdout=f,
            )

    files = parse_idt(tmp / "File.idt")
    comps = {c["Component"]: c for c in parse_idt(tmp / "Component.idt")}
    dirs = parse_idt(tmp / "Directory.idt")
    media = parse_idt(tmp / "Media.idt")

    dir_paths = build_dir_paths(dirs)
    install_full = list(install_subpath.parts)

    media_sorted = sorted(media, key=lambda m: int(m["LastSequence"]))

    def cab_for_seq(seq: int) -> str:
        for m in media_sorted:
            if seq <= int(m["LastSequence"]):
                return m["Cabinet"]
        return ""

    # 7z extract every named CAB into a flat staging dir. Cab member names
    # match File.File, so we can grab files by primary key downstream.
    stage = out_root.parent / "_msi_stage"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    seen: set[str] = set()
    for m in media_sorted:
        cab = m["Cabinet"]
        if not cab or cab in seen:
            continue
        seen.add(cab)
        cab_path = iso_dir / cab
        if not cab_path.exists():
            continue
        subprocess.run(
            [
                "7z",
                "x",
                "-y",
                "-bd",
                "-bb0",
                str(cab_path),
                f"-o{stage}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )

    placed = 0
    skipped_loose = 0
    skipped_outside = 0
    for f in files:
        seq = int(f["Sequence"])
        cab = cab_for_seq(seq)
        if not cab:
            # Loose disc file (Disk 11, Cabinet=""). Caller handles those.
            skipped_loose += 1
            continue
        key = f["File"]
        # FileName is "short|long" or just "short".
        fname = f["FileName"].split("|", 1)[-1]
        comp = comps[f["Component_"]]
        rel = list(dir_paths.get(comp["Directory_"], []))
        # Strip the leading install prefix so the result is rooted at $out.
        if rel[: len(install_full)] == install_full:
            rel = rel[len(install_full) :]
        else:
            # File targets a directory outside the game tree (System32
            # MFC/CRT helpers, etc.); Proton's prefix supplies those.
            skipped_outside += 1
            continue
        dest = out_root.joinpath(*rel, fname)
        expected_size = int(f["FileSize"] or 0)
        if dest.exists() and dest.stat().st_size == expected_size:
            continue
        src = stage / key
        if not src.exists():
            print(
                f"supplement_msi: WARN: {key} ({fname}) missing from staging",
                file=sys.stderr,
            )
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
        placed += 1

    shutil.rmtree(stage)
    shutil.rmtree(tmp)
    print(
        f"supplement_msi: placed {placed} previously-missing file(s); "
        f"{skipped_loose} loose-media entries deferred to caller; "
        f"{skipped_outside} entries skipped outside game tree"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
