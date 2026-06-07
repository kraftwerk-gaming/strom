{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Bridge Builder 2 / Bridge Construction Set (Chronic Logic, 2004).
  # Lutris has no entry for this title (slug bridge-builder-2 returns
  # 404 on lutris.net; the closest match on Lutris is the empty stub
  # "bridge-construction-set"). Tracked under bridge-builder-2 here
  # because that's the slug the rad issue (f2ac239) was opened with.
  #
  # The retail full version is still sold by Chronic Logic
  # (chroniclogic.com) and gated behind an email + keycode, so we
  # cannot legally redistribute the English retail .exe. The only
  # publicly archived full-game release is the 2004 German Halycon
  # Media re-publication of the Chronic Logic build, on archive.org
  # as item BridgeBuilderSpecialEditionGerman (MDF/MDS, ~65 MiB).
  # The German manual's first page reads:
  #   "BRIDGE BUILDER - BENUTZERHANDBUCH
  #    Copyright (c) 2004 Chronic Logic LLC
  #    Published (c) 2004 Halycon Media GmbH&Co.KG"
  # so the binary inside is the same Chronic Logic 2004 build, just
  # German-localised at the asset level (level filenames like
  # files/1-leicht, files/2-mittel, ... and on-screen German strings).
  #
  # The retail disc is laid out as:
  #   autorun.inf       DemoShield autorun (opens bb.exe)
  #   bb.exe, Bin/      DemoShield launcher + Bb.dbd UI database;
  #                     only relevant for browsing the CD's menu
  #   setup.exe         Wise installer, ~50 MiB. Wraps the real game.
  #   manual.pdf,       Documentation (also copied into MAINDIR by
  #   leveleditor.pdf   setup.exe).
  #
  # Wise installers can't be extracted by p7zip / cabextract /
  # innoextract / unshield, and nixpkgs doesn't ship a Wise
  # extractor; running setup.exe under wine is forbidden by the
  # project rules (no bare wine, including build-time tooling). So
  # the bake step was performed off-band:
  #   1. Convert Bridge Builder.mdf to ISO with mdf2iso.
  #   2. 7z-extract the ISO to get setup.exe.
  #   3. Run mnadareski/WiseUnpacker 2.1.0 (the C# port of REWise)
  #      on setup.exe to extract MAINDIR/ - the tree setup.exe would
  #      have written to C:\Programme\Bridge Builder\.
  #   4. Drop the Windows-only artefacts WiseUnpacker emits
  #      (BridgeBuilder.lnk shortcut, Unwise.exe uninstaller) and
  #      tar --zstd the rest as bridge-builder-2-install.tar.zst.
  #
  # Layout inside the tarball:
  #   BridgeBuilder.exe       main game (32-bit PE, SDL 1.x + OpenAL)
  #   Sdl.dll                 bundled SDL 1.2-era runtime
  #   OpenAL32.dll            bundled OpenAL Soft-style runtime
  #   data/                   shared engine assets
  #   model/, texture/        meshes and textures
  #   prop/                   in-world prop definitions (.pfo)
  #   sound/                  WAV/OGG sound effects
  #   files/1-leicht .. 5-extra   shipped level packs (leicht=easy,
  #                           mittel=medium, schwer=hard, komplex=
  #                           complex, extra=bonus)
  #   manual.pdf,             documentation (German)
  #   leveleditor.pdf
  #   hwconfig.cfg            engine hardware-detection cache; the
  #                           engine rewrites this on first run, so
  #                           it ends up in $STROM_GAMEDIR via the
  #                           fuse-overlayfs upper.
  #
  # fallbackUrl is empty because the published bytes (Bridge
  # Builder.mdf) are not the bake we ship. The original asset is
  # archive.org item BridgeBuilderSpecialEditionGerman; document it
  # here for the next contributor.
  src = fetchIpfs {
    cid = "Qmee5ebL8uQf1RX8QWz8mRResbuWvm9ET45d4h3VbQiJpR";
    fallbackUrl = "";
    hash = "sha256-q6JKTDfDp7OyxYRNwfXwaHh6/bIcBfQ59Z6P8qUT3eo=";
    name = "bridge-builder-2-install.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "bridge-builder-2";

  inherit src;

  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
  '';

  runtime = "proton";
  executable = "BridgeBuilder.exe";

  # The engine writes saved bridges and settings under
  # %USERPROFILE%\Documents\Bridge Construction Set\ on later
  # Chronic Logic builds; this 2004 German Halycon build instead
  # writes alongside BridgeBuilder.exe (hwconfig.cfg, saved bridges,
  # last-played settings). Top-level engine writes already land in
  # the fuse-overlayfs upper at $STROM_GAMEDIR via mk-game.nix, so
  # we leave saveLocations empty and revisit after interactive
  # testing confirms what the engine actually drops under
  # drive_c/users/steamuser/. Documents/Chronic Logic and
  # Documents/Bridge Construction Set are the candidate paths based
  # on the sibling Bridge Construction Set 1.39 builds; capture
  # them in Phase 2 if the engine creates either.
  saveLocations = [ ];

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
    description = "Bridge Builder 2 / Bridge Construction Set (Chronic Logic 2004, German Halycon release, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bridge-builder-2";
  };
}
