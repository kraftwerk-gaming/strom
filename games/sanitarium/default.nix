{
  self,
  lib,
  pkgs,
  fetchIpfs,
  scummvm,
  unzip,
  innoextract,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "sanitarium";

  # Sanitarium (DreamForge 1998, ASC Games / Daydream Software). The
  # GOG re-release wraps the original `Data/RES.*` resource files in a
  # ScummVM container; the GOG Inno installer ships a bundled Windows
  # scummvm.exe at the install root that auto-loads the "sanitarium"
  # target. We extract the GOG installer to get just the Data/ tree
  # and run native pkgs.scummvm against it -- no Proton needed.
  src = fetchIpfs {
    cid = "QmTaE4GSe356NYc8tHTpcLoHsaim6MA1JBPxRpTxsLFDGe";
    fallbackUrl = "https://archive.org/download/sanitarium_202602/Sanitarium.zip";
    hash = "sha256-tVMc1w0MC6T3aMeOLyi4+o2AOHgcR8vMaM863HQizo0=";
    name = "Sanitarium-gog.zip";
  };

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" "$TMPDIR/zip/Sanitarium/setup_sanitarium_1.0_svm_(57892).exe"
    # innoextract places `Data/`, `Saves/`, the bundled ScummVM, etc.
    # directly at the install root for this 5.6.2-era GOG installer
    # (no app/ wrapper). We need only the Data/ tree -- native
    # pkgs.scummvm drives it, so the bundled ScummVM/ and ISI
    # scriptinterpreter aren't needed and would just bloat the closure.
    cp -r "$TMPDIR/iss/Data" "$out/Data"
    mkdir -p "$out/Saves"
    cp "$TMPDIR/iss/readme.txt" "$out"/ 2>/dev/null || true
  '';

  runtime = "native";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  runScript = ''
    mkdir -p "$STROM_GAMEDIR/saves"
    # The RES.* resource files live in $GAMEDIR/Data, so --path points
    # there (not the overlay root). `asylum` is ScummVM's game id for
    # Sanitarium (the asylum engine, stable since ScummVM 2.6.0); the
    # bare "sanitarium" the GOG scummvm.ini uses is only a target alias,
    # not a game id, and native ScummVM rejects it as "Unrecognized".
    #
    # The asylum engine registers its `music_volume`/`sfx_volume`/
    # `speech_volume` config defaults on the original DirectSound
    # millibel scale (negative; -10000..0). ScummVM's base engine reuses
    # those same ConfMan keys as 0-256 mixer master volumes, so on an
    # ad-hoc launch (no game domain in scummvm.ini) Engine::syncSound-
    # Settings() feeds the negative asylum defaults straight into
    # setVolumeForSoundType(), which CLIP()s them to 0 -- muting the
    # kMusic/kSFX/kSpeech channels. Smacker cutscene audio rides the
    # kPlainSound channel (hard-pinned to max), so movies stayed audible
    # while all in-game music/SFX went silent. The GOG installer sidesteps
    # this by pre-seeding positive volumes in its sanitarium.ini; we pass
    # them explicitly on the command line instead.
    exec ${scummvm}/bin/scummvm \
      --fullscreen \
      --music-volume=192 \
      --sfx-volume=192 \
      --speech-volume=192 \
      --path="$GAMEDIR/Data" \
      --savepath="$STROM_GAMEDIR/saves" \
      asylum
  '';

  meta = {
    description = "Sanitarium (DreamForge 1998, GOG Windows release driven via native pkgs.scummvm)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sanitarium";
  };
}
