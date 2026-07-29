# GameImage FlatImage containers as an asset source (archive.org)

## Read this first: the titles lie

There is a family of ~70 archive.org items titled `<Game> - LINUX`, uploaded by
`beokos.kovac@gmail.com`. **They are not native Linux builds.** They are
WINDOWS games packed into [GameImage](https://github.com/ruanformigoni/gameimage)
FlatImage containers, which bundle their own `wine-tkg` and a pre-created
wineprefix. The item description says so in passing ("Game Packer run windows
games (softwares) on linux"), but the title, the `-linux` identifier suffix and
the `- LINUX` display name all invite the wrong conclusion.

If you trust the title you will set `runtime = "native"`, hunt for an ELF that
does not exist, and lose hours. Set `runtime = "proton"`.

This is still a **good** source: single-file, HTTP-range-friendly, with
archive.org publishing md5 + sha1 + size per file, so the bytes are verifiable
and a real non-IPFS `fallbackUrl` exists. That is exactly what several stage
branches are missing, and it is reachable headlessly (no Cloudflare challenge,
unlike the repack sites listed in `request-game-workflow.md`).

**We keep only the Windows game tree and throw the rest away.** The bundled
wine-tkg is never used: this repo is Proton-only (see AGENTS.md "Windows
compatibility runtime: Proton, never bare Wine"). Do not run the container's
own launcher, and do not run its `boot` ELF; extract and drive the tree with
`runtime = "proton"`.

## Finding items

`collection:` queries do not work for these; the items live in
`open_source_software`. Search by uploader or by the title convention:

    https://archive.org/advancedsearch.php?q=uploader%3A%22beokos.kovac%40gmail.com%22&rows=100&page=1&output=json&fl[]=identifier&fl[]=title&fl[]=item_size

Useful queries (plain `advancedsearch.php`, GET, no auth):

- `uploader:"beokos.kovac@gmail.com"` - the whole family (~70 items).
- `gameimage AND flatimage` - catches the same items via description text.
- `<game name> AND flatimage` - to check a single title.

Then `https://archive.org/metadata/<identifier>` for the per-file list with
`size`, `md5` and `sha1`. Prefer that endpoint over an HTTP HEAD: it is cheaper
and gives you checksums to verify against after downloading.

Titles present in the family include Skyrim, Oblivion, Pillars of Eternity,
Red Dead Redemption, Psychonauts, Mafia, Thief, Max Payne, Blade Runner,
Just Cause 2, Wasteland 2 Director's Cut, FIFA 13/16, NBA 2K9/2K10/2K11,
Myst I-V, Riven, Sam & Max, Dreamfall, Cryostasis, Shadowrun, Gray Matter,
Secret Files, The Black Mirror, Driver San Francisco, TrackMania United
Forever, GTR/GTR 2/GT Legends/Race 07, Hidden & Dangerous 2, Cold Fear,
The Punisher, GUN, Sanitarium, Blade Runner and a number of adventure games.

## Container format

A `.flatimage` is a single ELF executable with data appended:

    [ ELF launcher (fim_boot) + embedded static tools ]
    [ uint64 LE size ][ DwarFS image ]   <- layer 0
    [ uint64 LE size ][ DwarFS image ]   <- layer 1
    ...                                     to EOF

Each layer is a complete DwarFS filesystem preceded by its 8-byte little-endian
length. The offset where the layer chain begins is the value the launcher keeps
in its `.fim_reserved_offset` ELF section; the section table is stripped in
shipped images, so read it one of these ways:

- Ask the binary: `FIM_MAIN_OFFSET=1 ./Game.flatimage` prints the offset and
  exits (see `src/boot/relocate.hpp` in the flatimage source). This executes
  the container's launcher, which is fine (it is a CLI and opens no window),
  but it does unpack tools to a temp dir.
- Derive it offline, which is what the recipe below does: scan for the byte
  string `DWARFS`, and for each hit treat the preceding 8 bytes as a length;
  the correct starting offset is the one whose length chain walks to exactly
  EOF. Wrong guesses diverge immediately, so this is unambiguous in practice.

Walking the chain offline, for a file whose total size is `TOTAL`:

```python
import struct
layers, off = [], FIM_OFFSET
with open(path, "rb") as f:
    while off < TOTAL:
        f.seek(off)
        b = f.read(8)
        if len(b) < 8:
            break
        size = struct.unpack("<Q", b)[0]
        assert f.read(6) == b"DWARFS", f"no magic at {off + 8}"
        layers.append((off + 8, size))   # (offset, size) of the DwarFS image
        off += 8 + size
assert off == TOTAL, "chain did not land on EOF; wrong FIM_OFFSET"
```

Typical layer roles, lowest first: an Arch base rootfs, a unionfs overlay of
extra system packages, the wine build, **the game**, and a small `fim` config
layer. The game is normally by far the largest layer. Identify it by listing
each layer rather than assuming an index.

## Extracting

`dwarfsextract` (nixpkgs `dwarfs`, 0.14.0 at time of writing) reads a DwarFS
image, and `-O/--image-offset` can point it into the middle of a file. **But it
parses sections until end-of-file**, so it cannot read a layer in place: the
bytes just past the layer are the next layer's length prefix, which it
interprets as a section header and dies with

    dwarfs::runtime_error: [fs_section.cpp:50] truncated section header: ...
    dwarfs::runtime_error: [fs_section.cpp:67] truncated section data: ...

So carve the layer out first, then extract:

    dd if=Game.flatimage of=game.dwarfs bs=8M status=none \
      iflag=skip_bytes,count_bytes skip=<offset> count=<size>

    mkdir -p tree                      # dwarfsextract chdirs into -o
    dwarfsextract -i game.dwarfs -o tree --pattern "<path/inside>/**"

Two gotchas worth stating plainly:

- `-o` must already exist, otherwise you get
  `filesystem error: cannot set current path: No such file or directory`.
- List a layer with `-f mtree` before extracting, to find the game path and to
  confirm which layer you are looking at.

The Windows install sits inside the container's wineprefix, at roughly

    opt/gameimage-games/<Name>/wine/drive_c/<Install Dir>/

Extract that subtree only. `--pattern` copes with spaces and apostrophes in the
path when the argument is quoted.

## Packaging notes

- `src` is the whole `.flatimage`. Hash it as-is and set
  `fallbackUrl = "https://archive.org/download/<identifier>/<File>.flatimage"`.
  Never point `fallbackUrl` at an IPFS gateway (AGENTS.md).
- Add `dwarfs` to `nativeBuildInputs`.
- Hardcode the game layer's offset and size in the `let` block with a comment,
  and assert the `DWARFS` magic in `buildScript` so a wrong offset fails loudly
  instead of silently producing an empty tree. The `src` hash is pinned, so the
  offsets are deterministic.
- `rm` the carved layer copy before writing the tree to `$out`, so peak build
  disk stays near one payload instead of two.
- The container's prefix often contains junk the uploader installed next to the
  game (save editors, Total Commander, a JRE). Extract only the game directory.
- **`saveLocations` must still be derived empirically per title.** The
  container ships a pre-created *wine-tkg* prefix, and where that prefix has
  files is NOT evidence for where OUR Proton prefix will put saves: the
  uploader may have played the game, imported saves or run installers. Launch
  the game, reach a point where it writes, then list what appeared under
  `drive_c/users/steamuser` in our own prefix. See AGENTS.md "Save
  preservation across prefix wipes".
- Watch for a genuine Valve `steam_api64.dll` with no `goggame-*.info` beside
  it: that means the tree is a Steam build, not GOG. Say which in the header,
  because it changes what DRM shims are relevant.

## Worked example

`games/wasteland-2/default.nix` packages
[`wasteland-2-dc-linux`](https://archive.org/details/wasteland-2-dc-linux)
this way: 5 layers, game at offset 880377898 size 9741489424, install dir
`opt/gameimage-games/Wasteland-2-DC/wine/drive_c/Wasteland 2 Director's Cut`,
`runtime = "proton"`, bundled wine-tkg discarded. Verified headless to the main
menu.
