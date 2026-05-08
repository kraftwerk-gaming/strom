{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmZmFqNFqj5wG7pngQK3kXgTGnqAhzvfzaxj2WVXTPvekA";
    fallbackUrl = "https://ipfs.io/ipfs/QmZmFqNFqj5wG7pngQK3kXgTGnqAhzvfzaxj2WVXTPvekA";
    hash = "sha256-yLO+53ujzUnxcaJcXkh8GF9BCGN9PP+aTMJUTmqIUM8=";
    name = "leap-year-march.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "leap-year-march";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Leap.Year.v1.1.0.1/"* "$out"/
  '';

  runtime = "proton";
  # GameMaker Studio binary; the file name has spaces.
  executable = "Leap Year March.exe";

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
    description = "Leap Year: March (Daniel Linssen 2024, monthly project standalone, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "leap-year-march";
  };
}
