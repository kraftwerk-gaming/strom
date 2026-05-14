{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  shockolate = pkgs.callPackage ./shockolate.nix { };

  # System Shock (Looking Glass 1994, Enhanced CD release). Bin/cue rip
  # of the original USA CD-ROM (En,Fr,De) zipped on archive.org. CD root:
  #   CDROM/CDSHOCK.EXE   <- DOS Enhanced CD executable (unused; Shockolate
  #                          uses its own engine)
  #   CDROM/DATA          <- shared .res / .dat data files
  #   HD/DATA, HD/SOUND   <- the trees INSTALL.BAT copies to the C: drive
  #   INST/INITIAL.EXE    <- DOS installer (skipped)
  # Shockolate expects everything under `res/data/` and `res/sound/`
  # relative to its CWD; we merge HD/DATA + CDROM/DATA into res/data/ and
  # HD/SOUND into res/sound/. Night Dive's free 2018 GOG reissue
  # ("System Shock - Classic Edition") uses the same data files.

  # Tiny python ISO 9660 extractor: bsdtar/7z/fuseiso choke on the raw
  # MODE1/2352 bin layout, so we parse the volume descriptor and copy
  # the requested top-level directory entries by hand. Pulls HD/ (which
  # post-install lives at the C: install root) and CDROM/DATA/ (the
  # additional data files the EXE streams off the disc); both are
  # merged into the post-install layout by the build script.
  extractDirs = pkgs.writeText "extract-dirs.py" ''
    import os, struct, sys

    BIN = sys.argv[1]
    # Remaining args are pairs: <src-path-on-iso> <dest-dir>
    JOBS = list(zip(sys.argv[2::2], sys.argv[3::2]))

    def read_sector(f, lba, n=1):
        f.seek(lba * 2352)
        out = b""
        for _ in range(n):
            f.read(16)  # sync + header
            out += f.read(2048)
            f.read(288)  # ECC
        return out

    def parse_dir(f, lba, size):
        nsec = (size + 2047) // 2048
        data = read_sector(f, lba, nsec)
        i = 0
        out = []
        while i < len(data):
            rl = data[i]
            if rl == 0:
                i = ((i // 2048) + 1) * 2048
                if i >= len(data):
                    break
                continue
            entry = data[i:i + rl]
            elba = struct.unpack("<I", entry[2:6])[0]
            esize = struct.unpack("<I", entry[10:14])[0]
            flags = entry[25]
            nlen = entry[32]
            name = entry[33:33 + nlen].decode("ascii", errors="replace")
            if ";" in name:
                name = name.split(";", 1)[0]
            is_dir = (flags & 2) != 0
            if name and name not in ("\x00", "\x01"):
                out.append((name, is_dir, elba, esize))
            i += rl
        return out

    def find_dir(f, lba, size, components):
        if not components:
            return (lba, size)
        head, tail = components[0], components[1:]
        for name, is_dir, elba, esize in parse_dir(f, lba, size):
            if is_dir and name.upper() == head.upper():
                return find_dir(f, elba, esize, tail)
        raise SystemExit("path not found on disc: " + "/".join(components))

    def extract(f, lba, size, dest):
        os.makedirs(dest, exist_ok=True)
        for name, is_dir, elba, esize in parse_dir(f, lba, size):
            child = os.path.join(dest, name)
            if is_dir:
                extract(f, elba, esize, child)
            else:
                nsec = (esize + 2047) // 2048
                data = read_sector(f, elba, nsec)[:esize]
                with open(child, "wb") as out:
                    out.write(data)

    with open(BIN, "rb") as f:
        pvd = read_sector(f, 16)
        assert pvd[1:6] == b"CD001", "not iso9660"
        root_lba = struct.unpack("<I", pvd[156 + 2:156 + 6])[0]
        root_size = struct.unpack("<I", pvd[156 + 10:156 + 14])[0]
        for src, dest in JOBS:
            comps = [c for c in src.split("/") if c]
            lba, size = find_dir(f, root_lba, root_size, comps)
            extract(f, lba, size, dest)
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "system-shock";

  src = fetchIpfs {
    cid = "QmWiPSJPawVFTjhBfhWHUz2Sfg84hcecZzW8jMCCThHCKC";
    fallbackUrl = "https://archive.org/download/SystemShockUSAEnFrDe/System%20Shock%20%28USA%29%20%28En%2CFr%2CDe%29.zip";
    hash = "sha256-SzzRWcUzTwmVG/DMJxI1RN1luE74cZbnC9pu11CMUEc=";
    name = "system-shock.zip";
  };

  nativeBuildInputs = [
    pkgs.unzip
    pkgs.python3
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/iso"
    unzip -q "$src" -d "$TMPDIR/zip"
    BIN="$TMPDIR/zip/System Shock (USA) (En,Fr,De).bin"

    # Pull HD/ (what INSTALL.BAT stages to the C: drive: DATA + SOUND)
    # and CDROM/DATA/ (the additional data the CD edition reads off the
    # disc at runtime). Merge into the post-install layout Shockolate
    # expects: res/data/ holds every .res / .dat, res/sound/ holds the
    # XMI music + AdLib/SoundBlaster patches.
    python3 ${extractDirs} "$BIN" \
      HD              "$TMPDIR/iso/hd" \
      CDROM/DATA      "$TMPDIR/iso/cddata"

    mkdir -p "$out/res/data" "$out/res/sound"
    # HD/DATA -> res/data (write first; will be overlaid by CDROM/DATA).
    if [ -d "$TMPDIR/iso/hd/DATA" ]; then
      cp -r "$TMPDIR/iso/hd/DATA"/. "$out/res/data"/
    fi
    if [ -d "$TMPDIR/iso/hd/SOUND" ]; then
      cp -r "$TMPDIR/iso/hd/SOUND"/. "$out/res/sound"/
    fi
    # CDROM/DATA overlays HD/DATA with the CD-only files (audio logs,
    # SVGA cutscenes). Any name collisions resolve in favour of the CD
    # version, which is the Enhanced Edition data Shockolate expects.
    cp -rn "$TMPDIR/iso/cddata"/. "$out/res/data"/
    chmod -R u+w "$out/res"
    # Lowercase every filename: the original ISO is ALL CAPS, but
    # Shockolate's source hard-codes lowercase relative paths like
    # `res/data/cybstrng.res`. Case-fold across both res/ subtrees in
    # one pass.
    find "$out/res" -depth -execdir sh -c '
      for f; do
        lc=$(printf "%s" "$f" | tr "[:upper:]" "[:lower:]")
        [ "$f" = "$lc" ] || mv -- "$f" "$lc"
      done
    ' _ {} +

    # Shockolate's non-Apple OpenGL loader fopen's `shaders/<name>`
    # relative to the runtime CWD. mk-game's native runtime chdirs to
    # the per-game overlay, so drop the shader tree at the overlay root.
    cp -r ${shockolate}/share/shockolate-shaders "$out/shaders"
  '';

  copyGlobs = [ ];

  runtime = "native";
  executable = lib.getExe shockolate;

  # Shockolate writes savegames + shockolate.cfg into the CWD (the
  # overlay), so they land in ~/.strom/system-shock/ via the overlay.
  saveLocations = [ ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "System Shock (Looking Glass 1994, Enhanced CD edition, via Shockolate)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "system-shock";
  };
}
