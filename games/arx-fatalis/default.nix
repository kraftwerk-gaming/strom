{
  self,
  lib,
  pkgs,
  fetchIpfs,
  arx-libertatis,
  innoextract,
  gnutar,
}:

let
  # Arx Fatalis (Arkane Studios 2002). Runs natively via Arx Libertatis,
  # the open-source engine reimplementation. The proprietary data files
  # are extracted from the GOG.com installer (v1.22, Inno Setup with
  # GOG Galaxy split: setup_arx_fatalis_1.22_(38577).exe plus the
  # accompanying -1.bin data slob). innoextract 1.7+ reassembles the
  # split parts automatically when both files live in the same directory.
  # The two files are bundled into a single tarball so fetchIpfs can
  # treat them as one artifact.
  src = fetchIpfs {
    cid = "QmTFNMEDJk9QitB3HoFkDeo12vD6UHqTzZgaStaRvBgC8T";
    fallbackUrl = "https://archive.org/details/arx_fatalis_GOG";
    hash = "sha256-+tHz+57k778oygBXF43C/PIs+cl7w32qDWUxf7EgjG0=";
    name = "arx-fatalis-gog.tar";
  };

  # The GOG release ships misc/logo.avi (~2.4 MiB) with only the Arkane
  # Studios logo segment; the original retail CD shipped a 28 MiB
  # logo.avi at bin/logo.avi that contains both the Arkane logo AND the
  # full game intro (the Atlantean prologue narrated over the title
  # crawl). Without it the game opens directly on the prison-cell
  # scene, which feels abrupt and skips the entire backstory. Source:
  # extracted from the retail CD image at archive.org/details/
  # arx_Fatalis_2002 (Arx.iso, bin/logo.avi).
  intro = fetchIpfs {
    cid = "QmVoEDREzChs6XbDmt7NxWZRoiBaitoQkWanAKDxWGvRGk";
    hash = "sha256-EAzsGVtB/RgSOx6b/P7bBDtnQ3oZQX3YdjcyVG2ghAg=";
    name = "arx-fatalis-intro.avi";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "arx-fatalis";

  inherit src;
  ipfsSources = [
    src
    intro
  ];

  nativeBuildInputs = [
    gnutar
    innoextract
  ];

  # Untar the bundled GOG installer parts side-by-side, then innoextract
  # the .exe (it pulls bytes from the .bin GOG-Galaxy slob in the same
  # directory). The game data lands at the extract root: data.pak,
  # data2.pak, loc.pak, sfx.pak, speech.pak, graph/, misc/, plus a few
  # GOG-specific helper files we drop. The "app/" subdir only contains
  # GOG launcher metadata; the engine doesn't need it.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/gog"
    tar -xf "$src" -C "$TMPDIR/gog"
    innoextract -d "$TMPDIR/extract" -e "$TMPDIR/gog"/setup_arx_fatalis_*.exe
    cp -r "$TMPDIR/extract"/. "$out"/
    # Drop GOG/Windows-only cruft. The engine only needs the .pak files,
    # graph/, misc/, and the localisation/ tree.
    rm -rf "$out/__redist" "$out/app" "$out/commonappdata" "$out/tmp"
    rm -f "$out"/goggame-*.{hashdb,info,script} \
          "$out/Athena.dll" "$out/arx.exe" "$out/arx.bat" \
          "$out/unicows.dll" "$out/game.ico" "$out/cfg.ini" \
          "$out/cfg_default.ini"
    # Replace the GOG-stripped logo.avi (Arkane logo only, ~2.4 MiB)
    # with the retail-CD version that includes the full game intro.
    cp ${intro} "$out/misc/logo.avi"
  '';

  runtime = "native";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # SDL2 toggles cursor visibility between menu and gameplay; without
      # this, gamescope doesn't reliably re-enter relative-mouse mode and
      # the camera input becomes laggy/clipped.
      "--force-grab-cursor" = true;
    };
  };

  # arx-libertatis searches XDG paths + its compile-time prefix for the
  # data files; cwd is not in the list, so -d "$GAMEDIR" is required to
  # point it at the overlay. Saves/config land under $HOME (=
  # $STROM_GAMEDIR) via the engine's XDG defaults.
  runScript = ''
    exec ${arx-libertatis}/bin/arx -d "$GAMEDIR"
  '';

  meta = {
    description = "Arx Fatalis (Arkane Studios 2002, via Arx Libertatis)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "arx-fatalis";
  };
}
