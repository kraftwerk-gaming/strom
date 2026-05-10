{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmVhSd1hiMBQwCXcgASGp9wm7PbMX2GrJ6Ziwcs5vp4re5";
    fallbackUrl = "https://ipfs.io/ipfs/QmVhSd1hiMBQwCXcgASGp9wm7PbMX2GrJ6Ziwcs5vp4re5";
    hash = "sha256-Ml7m3HHH83Upr659djWDYydRVb+cL2DRYBbp2wII7MY=";
    name = "leap-year.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "leap-year";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Leap.Year.Build.17614177/"* "$out"/
  '';

  runtime = "proton";
  # GameMaker Studio binary; the file name has spaces.
  executable = "Leap Year.exe";

  saveLocations = [ "AppData/Local/Leap_Year" ];

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

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Leap Year (Daniel Linssen 2025, Steam Build 17614177, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "leap-year";
  };
}
