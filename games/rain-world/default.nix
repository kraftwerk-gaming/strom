{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG Windows release of Rain World 1.9.07b-v3 (build 63290) — the
  # base game without the Downpour DLC. The setup is a two-part GOG
  # installer (.exe + .bin slice). innoextract reads them together when
  # they sit next to each other; the inputs are FODs so we place
  # symlinks in $TMPDIR with the original filenames before extracting.
  setupExe = fetchIpfs {
    cid = "QmWtc45sv19XtZMsZ7SjURAzRnoPfoKde32jTZMpPazeKA";
    fallbackUrl = "https://archive.org/download/rain-world/Rain_World_1.9.07b-v3_%2863290%29_win_gog/setup_rain_world_03-21-2023-1.9.07b-v3_%2863290%29.exe";
    hash = "sha256-PoDYtJ3SdBb+2pT03RHhRQbvJ9kuQlz9AmIuyepR/c8=";
    name = "rain-world-gog-1.9.07b-v3.exe";
  };

  setupBin = fetchIpfs {
    cid = "QmV1RaqTtCoRs2Rh3k1nkcX1d3svgjFWBfB9WdWVGfJFZw";
    fallbackUrl = "https://archive.org/download/rain-world/Rain_World_1.9.07b-v3_%2863290%29_win_gog/setup_rain_world_03-21-2023-1.9.07b-v3_%2863290%29-1.bin";
    hash = "sha256-usIfo4bRjg4GAibvlh/wLx0c+MapTLFKjhkg8aGdcX4=";
    name = "rain-world-gog-1.9.07b-v3-1.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "rain-world";

  ipfsSources = [
    setupExe
    setupBin
  ];

  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    # innoextract requires the .exe and .bin to share a directory and
    # use the GOG-original filenames so it can find the slice.
    mkdir -p "$TMPDIR/rw"
    ln -s ${setupExe} "$TMPDIR/rw/setup_rain_world_03-21-2023-1.9.07b-v3_(63290).exe"
    ln -s ${setupBin} "$TMPDIR/rw/setup_rain_world_03-21-2023-1.9.07b-v3_(63290)-1.bin"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/rw/setup_rain_world_03-21-2023-1.9.07b-v3_(63290).exe"
    # innoextract drops the game (RainWorld.exe, MonoBleedingEdge,
    # RainWorld_Data, BepInEx) at the root of $TMPDIR/iss; app/ holds
    # the StreamingAssets the GOG installer slots into RainWorld_Data,
    # plus webcache and __redist we don't need.
    cp -r "$TMPDIR/iss"/* "$out/"
    if [ -d "$out/app/RainWorld_Data/StreamingAssets" ]; then
      mkdir -p "$out/RainWorld_Data"
      cp -r "$out/app/RainWorld_Data/StreamingAssets" "$out/RainWorld_Data/"
    fi
    rm -rf "$out/app" "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata" "$out/webcache.zip" 2>/dev/null || true
  '';

  runtime = "proton";
  executable = "RainWorld.exe";

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
    description = "Rain World (Videocult, GOG v1.9.07b-v3 build 63290, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rain-world";
  };
}
