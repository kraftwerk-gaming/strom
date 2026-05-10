{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  msitools,
  runCommandLocal,
}:

let
  # Far Cry (Crytek/Ubisoft, 2004 PC retail). DVD ISO of the FARCRY_1
  # multilingual release; the ISO holds an MSI installer (FC32.msi) that
  # pulls files out of a sequence of CABs (PB / Binaries / Game / French /
  # English / Data1..4 / Data21).
  gameISO = fetchIpfs {
    cid = "QmSeBi5c7WXQziStu72ocgCMsUoHGZKd3v1VFTWd8RLAVJ";
    fallbackUrl = "https://archive.org/download/farcry_202502/Farcry.iso";
    hash = "sha256-hgcttoYo7ay1qrmYqPsl0sNa8658JDHlW6bfwklkBf4=";
    name = "far-cry.iso";
  };

  # Driving the Wine-based InstallShield-Wizard front-end is messy under
  # bwrap; instead extract the MSI and CABs directly with msitools'
  # `msiextract`, then flatten the directory chain it produces. msitools
  # encodes the original MSI Directory hierarchy by suffixing intermediate
  # path components with `:.` and joining them with `/`, e.g.
  #   "Program Files/Ubisoft:./Crytek:./Far Cry:./Bin32:./FarCry.exe".
  # We strip the trailing ":." from every directory name (depth-first) so
  # the result is a normal POSIX tree rooted at "Program Files".
  gameData =
    runCommandLocal "far-cry-data"
      {
        nativeBuildInputs = [
          p7zip
          msitools
          pkgs.python3
        ];
      }
      ''
        mkdir -p iso
        # Pull the MSI plus all CABs the MSI's Media table references.
        7z x -y ${gameISO} -oiso \
          FC32.msi PB.cab Binaries.cab Game.cab \
          French.cab English.cab \
          Data1.cab Data2.cab Data3.cab Data4.cab Data21.cab

        mkdir -p extract
        # msiextract exits non-zero even on otherwise-successful runs
        # (Data2.cab + Data21.cab form a multi-volume cabinet that
        # msitools mishandles with "Invalid folder index", silently
        # dropping ~22 files including FCData/Music.pak, FCData/Sounds.pak,
        # FCData/Objects.pak and Languages/Movies/DemoLoops/CryTek.bik).
        # Tolerate non-zero here; the supplement step below recovers the
        # missing files via 7z and the MSI File/Component/Directory tables.
        msiextract -C extract iso/FC32.msi || true

        # Flatten msiextract's encoded paths: rename any directory whose
        # basename ends in ":." to drop the suffix. Process deepest first
        # so parents stay accessible until their children are renamed.
        find extract -depth -type d -name '*:.' -print0 \
          | while IFS= read -r -d "" d; do
              new="''${d%:.}"
              if [ "$new" != "$d" ]; then
                mv -- "$d" "$new"
              fi
            done

        # The same encoding can produce a top-level ".:System32" for
        # files that target the Windows system directory; rename it the
        # same way (leading ".:" → "."). We don't need those DLLs on
        # Proton (vcrun71/mfc71 ship with Wine prefixes), but keep them
        # for completeness.
        if [ -d 'extract/.:System32' ]; then
          mv 'extract/.:System32' 'extract/System32'
        fi

        # Promote the actual game tree to the output root.
        mkdir -p "$out"
        cp -a 'extract/Program Files/Ubisoft/Crytek/Far Cry/.' "$out"/

        # FarCry.exe is the small (~32 KB) bootstrap binary that lives
        # loose on the disc root rather than inside any CAB; the MSI's
        # Media table records it as DiskId 11 with an empty Cabinet
        # (sequence 617, past the last cab's LastSequence=602). msitools
        # does not currently extract such "loose" media-table entries,
        # so pull FarCry.exe out of the ISO directly and drop it next to
        # the engine DLLs in Bin32/ where the game expects it.
        7z x -y -so ${gameISO} FarCry.exe > "$out/Bin32/FarCry.exe"

        # The intro/outro .bik movies (English + French) also live loose
        # on the disc root rather than in any CAB (their MSI rows have
        # DiskId=11, Cabinet=""); pull them straight out of the ISO into
        # the directory layout the engine expects, otherwise the game
        # null-derefs trying to play CryTek.bik right after engine init
        # ("CRITICAL ERROR" right after `Loading DevMode.lua: Ok!`).
        7z x -y ${gameISO} \
          -o"$out" \
          'Languages/Movies/English/*.bik' \
          'Languages/Movies/French/*.bik'

        # Recover anything msiextract dropped due to the Data2/Data21
        # multi-volume "Invalid folder index" failure. We re-extract every
        # named CAB with 7z (which handles the volume continuation) into a
        # flat staging dir keyed by File.File (the GUID-ish key, which
        # matches the cab member name), then walk the MSI File / Component
        # / Directory tables to compute the proper path under the game
        # root for every file we still don't have, and copy it into place.
        python3 ${./supplement_msi.py} \
          iso "$out" 'Ubisoft/Crytek/Far Cry' iso/FC32.msi

        # Fail loudly if either bootstrap or engine DLLs are missing,
        # or if the supplement step didn't manage to recover the files
        # the engine refuses to start without.
        test -f "$out/Bin32/FarCry.exe" \
          || { echo "FarCry.exe missing from extracted tree" >&2; exit 1; }
        test -f "$out/Bin32/CryGame.dll" \
          || { echo "CryGame.dll missing from extracted tree" >&2; exit 1; }
        test -f "$out/FCData/Music.pak" \
          || { echo "FCData/Music.pak missing from extracted tree" >&2; exit 1; }
        test -f "$out/FCData/Sounds.pak" \
          || { echo "FCData/Sounds.pak missing from extracted tree" >&2; exit 1; }
        test -f "$out/Languages/Movies/English/Crytek.bik" \
          || { echo "Languages/Movies/English/Crytek.bik missing" >&2; exit 1; }

        # Bump the shipped resolution from 1024x768 to 1920x1080, force
        # fullscreen, and disable r_VolumetricFog: its shader fails to
        # compile under DXVK and the engine then null-derefs during 3D
        # init when starting the campaign (CTexMan::ImagePreprocessing →
        # TemplVFog Compile Fail → CRITICAL ERROR). The engine warns it
        # rewrites this file at runtime, but our fuse-overlayfs gives
        # the game a writable copy on top of this read-only baseline.
        sed -i \
          -e 's/^r_Width = .*/r_Width = "1920"/' \
          -e 's/^r_Height = .*/r_Height = "1080"/' \
          -e 's/^r_Fullscreen = .*/r_Fullscreen = "1"/' \
          -e 's/^r_VolumetricFog = .*/r_VolumetricFog = "0"/' \
          "$out/system.cfg"
        grep -q '^r_VolumetricFog' "$out/system.cfg" \
          || echo 'r_VolumetricFog = "0"' >> "$out/system.cfg"
      '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "far-cry";

  ipfsSources = [ gameISO ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "proton";
  executable = "Bin32/FarCry.exe";
  # `-DEVMODE` unlocks the engine's developer cvars and, more usefully,
  # disables the disc check that otherwise crashes the game on campaign
  # start without the original DVD inserted.
  executableArgs = [ "-DEVMODE" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Far Cry (Crytek/Ubisoft, 2004 retail DVD, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "far-cry";
  };
}
