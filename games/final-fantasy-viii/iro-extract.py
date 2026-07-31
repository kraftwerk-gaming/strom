#!/usr/bin/env python3
r"""Extract an IRO archive (.iroj) into a plain file tree.

IRO is the container format 7th Heaven and its FF8 fork Junction VIII use
for mods, and every mod in the Tsunamods catalogue ships as one -- textures,
music, FMVs and gameplay alike. Junction VIII needs a Windows GUI to apply
them; this reads the same archives so the contents can be stacked as an
overlay lower instead.

Format, ported from Junction VIII's AppWrapper/IrosArc.cs (MS-PL):

    header      int32 signature == 0x534F5249 ("IROS")
                int32 version (0x10000..0x10002)
                int32 archive flags
                int32 directory offset

    directory   int32 count, or -1 followed by an int64 giving the real
                directory offset (used by patched archives; loop until
                count >= 0)

    entry       uint16 total entry length
                uint16 filename byte length
                bytes  filename, UTF-16LE, backslash separated
                int32  flags: 0x1 LZS, 0x2 LZMA
                int64  data offset (int32 when version < 0x10001)
                int32  data length
                (skip to entry start + total length)

LZMA payloads are the 7-Zip "alone" framing, which Python decodes directly.
LZS is not implemented: nothing in the catalogue uses it, and hitting it
raises rather than silently dropping a file.

A mod's own mod.xml decides which subtrees apply:

    <ModFolder Folder="Horizonpack" ActiveWhen="horizonpack_ID = 1" />
    <ConfigOption> ... <ID>horizonpack_ID</ID> <Default>1</Default> </ConfigOption>

Each top-level folder is gated on a config variable. Without Junction
VIII's UI the variables come from their declared defaults, overridable with
--set ID=VALUE. Active folders are merged into the output root, so a mod
laid out as `Horizonpack\mods\textures\...` lands as `mods/textures/...`
next to the game executable, which is where FFNx looks.
"""

from __future__ import annotations

import argparse
import lzma
import pathlib
import re
import struct
import sys

IRO_SIG = 0x534F5249
VERSION_MIN = 0x10000
VERSION_MAX = 0x10002
FLAG_LZS = 0x1
FLAG_LZMA = 0x2


class IroError(Exception):
    """Raised for anything malformed enough that guessing would be wrong."""


def parse_entries(buf: bytes) -> tuple[int, list[dict]]:
    sig, version, _flags, dirpos = struct.unpack_from("<iiii", buf, 0)
    if sig != IRO_SIG:
        raise IroError(f"signature mismatch: 0x{sig:08X}")
    if not VERSION_MIN <= version <= VERSION_MAX:
        raise IroError(f"unsupported version 0x{version:X}")

    pos = dirpos
    while True:
        (count,) = struct.unpack_from("<i", buf, pos)
        pos += 4
        if count >= 0:
            break
        (pos,) = struct.unpack_from("<q", buf, pos)

    entries = []
    for _ in range(count):
        start = pos
        entry_len, name_len = struct.unpack_from("<HH", buf, pos)
        pos += 4
        name = buf[pos : pos + name_len].decode("utf-16-le")
        pos += name_len
        (flags,) = struct.unpack_from("<i", buf, pos)
        pos += 4
        if version < 0x10001:
            (offset,) = struct.unpack_from("<i", buf, pos)
            pos += 4
        else:
            (offset,) = struct.unpack_from("<q", buf, pos)
            pos += 8
        (length,) = struct.unpack_from("<i", buf, pos)
        pos += 4
        entries.append(
            {"name": name, "flags": flags, "offset": offset, "length": length}
        )
        pos = start + entry_len

    return version, entries


def read_entry(buf: bytes, entry: dict) -> bytes:
    raw = buf[entry["offset"] : entry["offset"] + entry["length"]]
    if entry["flags"] & FLAG_LZMA:
        return lzma.decompress(raw, format=lzma.FORMAT_ALONE)
    if entry["flags"] & FLAG_LZS:
        raise IroError(f"{entry['name']}: LZS compression is not implemented")
    return raw


def active_folders(mod_xml: str, overrides: dict[str, str]) -> set[str]:
    """Resolve ModFolder gates against ConfigOption defaults."""
    settings: dict[str, str] = {}
    for block in re.findall(r"<ConfigOption>.*?</ConfigOption>", mod_xml, re.S):
        ident = re.search(r"<ID>(.*?)</ID>", block, re.S)
        default = re.search(r"<Default>(.*?)</Default>", block, re.S)
        if ident and default:
            settings[ident.group(1).strip().lower()] = default.group(1).strip()
    settings.update({k.lower(): v for k, v in overrides.items()})

    folders = set()
    for folder, when in re.findall(
        r'<ModFolder\s+Folder="([^"]+)"(?:\s+ActiveWhen="([^"]*)")?\s*/?>', mod_xml
    ):
        if not when:
            folders.add(folder)
            continue
        cond = re.match(r"\s*([A-Za-z0-9_]+)\s*=\s*([0-9]+)\s*$", when)
        if not cond:
            # Anything more complex than "var = value" is not something to
            # guess at; keeping the folder out is the safe direction.
            print(
                f"iro-extract: skipping {folder!r}: unparsed {when!r}", file=sys.stderr
            )
            continue
        ident, value = cond.group(1).lower(), cond.group(2)
        if settings.get(ident) == value:
            folders.add(folder)

    return folders


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("archive", type=pathlib.Path)
    ap.add_argument("outdir", type=pathlib.Path)
    ap.add_argument(
        "--set",
        action="append",
        default=[],
        metavar="ID=VALUE",
        help="override a mod.xml ConfigOption default",
    )
    ap.add_argument(
        "--list", action="store_true", help="list entries and folders, extract nothing"
    )
    ap.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="FOLDER",
        help="take only these top-level folders, ignoring mod.xml gates "
        "(case-insensitive; for mods whose ModFolder elements carry no "
        "ActiveWhen and are therefore always active)",
    )
    args = ap.parse_args()

    overrides = {}
    for item in args.set:
        if "=" not in item:
            ap.error(f"--set expects ID=VALUE, got {item!r}")
        key, value = item.split("=", 1)
        overrides[key.strip()] = value.strip()

    buf = args.archive.read_bytes()
    version, entries = parse_entries(buf)

    mod_xml_entry = next((e for e in entries if e["name"].lower() == "mod.xml"), None)
    mod_xml = (
        read_entry(buf, mod_xml_entry).decode("utf-8", "replace")
        if mod_xml_entry
        else ""
    )
    folders = active_folders(mod_xml, overrides) if mod_xml else set()

    if args.only:
        prefixes = {f.lower().strip("\\") for f in args.only}
        matched = {
            "\\".join(e["name"].split("\\")[: p.count("\\") + 1])
            for e in entries
            for p in prefixes
            if e["name"].lower().startswith(p + "\\")
        }
        missing = [
            f
            for f in args.only
            if not any(m.lower() == f.lower().strip("\\") for m in matched)
        ]
        if missing:
            tops = sorted(
                {e["name"].split("\\")[0] for e in entries if "\\" in e["name"]}
            )
            raise IroError(
                f"--only named folders not in the archive: {sorted(missing)}; "
                f"top-level folders present: {tops}"
            )
        folders = matched

    if args.list:
        print(f"version 0x{version:X}, {len(entries)} entries")
        print(f"active folders: {sorted(folders)}")
        for e in entries:
            print(f"  {e['flags']:#x} {e['length']:>10} {e['name']}")
        return 0

    # A ModFolder may name a nested subtree ("FIELD_MODELS\HIGH_POLY"), so
    # match at the declared depth rather than assuming one component, and
    # strip exactly that prefix. Deepest match wins, so a mod gating both a
    # parent and its child does not extract the child twice.
    depths = sorted({f.count("\\") + 1 for f in folders}, reverse=True)

    written = 0
    for entry in entries:
        parts = entry["name"].split("\\")
        rel = next(
            (
                parts[d:]
                for d in depths
                if len(parts) > d and "\\".join(parts[:d]) in folders
            ),
            None,
        )
        if rel is None:
            continue  # inactive subtree, or metadata like mod.xml at the root
        dest = args.outdir.joinpath(*rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(read_entry(buf, entry))
        written += 1

    if written == 0:
        raise IroError(
            f"no files extracted; active folders {sorted(folders)} matched nothing"
        )

    print(f"iro-extract: {written} files from {sorted(folders)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
