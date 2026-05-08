{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmR8tacot64jvaZn8ZV2J9Gh8dxDqKy2c7MW6aSo2UC9MN";
    fallbackUrl = "https://ipfs.io/ipfs/QmR8tacot64jvaZn8ZV2J9Gh8dxDqKy2c7MW6aSo2UC9MN";
    hash = "sha256-7KHYRSmJzqvhmU33FFHYfePg+BGGj33617jmw37Ns0c=";
    name = "everhood-repackgames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "everhood";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Everhood.Build.16890688/"* "$out"/
  '';

  runtime = "proton";
  executable = "Everhood.exe";

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
    description = "Everhood (Chris Nordgren 2021, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "everhood";
  };
}
