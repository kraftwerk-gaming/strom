{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmVP4fju6q57QgZg441JTpfgPid8wy5NFkjcavnX5dFwqD";
    fallbackUrl = "https://ipfs.io/ipfs/QmVP4fju6q57QgZg441JTpfgPid8wy5NFkjcavnX5dFwqD";
    hash = "sha256-WqaI0fElDvLrnSDwkwWU0eJpVk7ZkcqpXrEpkxXcoBY=";
    name = "ball-x-pit-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "ball-x-pit";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/BALLxPIT/"* "$out"/
  '';

  runtime = "proton";
  executable = "Balls.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Ball x Pit (Kenny Sun 2024, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "ball-x-pit";
  };
}
