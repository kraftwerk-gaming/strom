{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Nice Day for Fishing (FusionPlay / Team17, 2025), GOG offline installer
  # v1.2.15, Windows-only (~640 MB, GOG product id 1538573490, Steam app
  # 2393160). Unity fishing RPG; runs under Proton.
  #
  # Source: GOG offline installer obtained via freegogpcgames magnet
  #   magnet:?xt=urn:btih:3D75712115122719589E67FCC5B8FF0EE2922B81
  # innoextract --gog places game files at extraction root (no app/ subdir).
  src = fetchIpfs {
    cid = "QmZCgP8XjfWpmc5fPXDybTCykETXUumLupyJRXoF8b7op3";
    fallbackUrl = "https://api.gog.com/products/1538573490/downlink/installer/en1installer0";
    hash = "sha256-/6znFP3YJedAqNW6l9t+C9YUt7PANAoq3h5lUTSX2v8=";
    name = "setup_nice_day_for_fishing_1.2.15.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "nice-day-for-fishing";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/iss" "$src"
    # GOG Unity installer: files are at extraction root, not under app/
    cp -r "$TMPDIR/iss"/. "$out"/
    # GOG installer debris + Galaxy support: not needed at runtime.
    rm -rf "$out/__redist" "$out/__support" "$out/app" "$out/commonappdata" "$out/tmp"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico
  '';

  runtime = "proton";
  # Confirmed from GOG installer: Unity game, exe at root (capital F in "For")
  executable = "Nice Day For Fishing.exe";

  # Unity games typically write saves under AppData/LocalLow. Adjust after test.
  saveLocations = [ "AppData/LocalLow/FusionPlay/Nice Day For Fishing" ];

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
    description = "Nice Day for Fishing (FusionPlay / Team17 2025, GOG v1.2.15, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "nice-day-for-fishing";
  };
}
