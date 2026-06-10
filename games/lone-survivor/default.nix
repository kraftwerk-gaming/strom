{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  src = fetchIpfs {
    cid = "QmcwMQYu7baPa7Ans6yM6ARCfZLx8htu9z32Ao2DvrjwwX";
    fallbackUrl = "https://gog-games.to/game/lone_survivor_directors_cut";
    hash = "sha256-hsH1IA0RvmokW3xOSIPLnVM6C3F7TPw8tifLwYDoYTM=";
    name = "setup_lone_survivor_the_directors_cut_1.0_21178.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "lone-survivor";

  inherit src;

  nativeBuildInputs = [
    innoextract
  ];

  # GOG ships the game at the installer root (not under app/): the AIR
  # launcher exe, LoneSurvivor.swf content, the bundled captive "Adobe
  # AIR" runtime and the META-INF descriptor all sit at the top level.
  # Only the icon/webcache live under app/, so copy the root and drop the
  # installer bookkeeping.
  buildScript = ''
    mkdir -p "$TMPDIR/iss"
    innoextract --gog --exclude-temp -d "$TMPDIR/iss" "$src"

    mkdir -p "$out"
    cp -r "$TMPDIR/iss"/. "$out"/
    rm -rf "$out/__redist" "$out/commonappdata" "$out/app"
    rm -f "$out"/goggame-*
  '';

  runtime = "proton";
  executable = "LoneSurvivor-TheDirectorsCut.exe";

  # Lone Survivor is an Adobe AIR (captive-runtime) app; AIR's encrypted
  # local store / shared objects land under %APPDATA%\Roaming in an
  # app-id+publisher-hash folder that is awkward to predict ahead of a
  # first launch. Let saves ride the per-game fuse-overlayfs upper instead
  # of symlinking a guessed path.
  saveLocations = [ ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "Lone Survivor: The Director's Cut (Superflat Games, GOG v1.0 build 21178, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "lone-survivor";
  };
}
