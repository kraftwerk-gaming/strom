{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  src = fetchIpfs {
    cid = "QmXqGFXAh7Y9vzBRXj5cGyjnLFPPsYnMJPZVAoMAbdWmtj";
    hash = "sha256-hi9tn6HC6pgLIAkAoZtnhus7BcYq8B241xBVWqvupoM=";
    name = "balatro-ankergames.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "balatro";

  ipfsSources = [ src ];

  src =
    pkgs.runCommandLocal "balatro-data"
      {
        nativeBuildInputs = [ pkgs.unar ];
      }
      ''
        mkdir -p "$out"
        unar -o "$out" ${src}
        extracted=$(echo "$out/"*/)
        mv "$extracted/Balatro/"* "$out/"
      '';

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "proton";
  executable = "Balatro.exe";

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
    description = "Balatro (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "balatro";
  };
}
