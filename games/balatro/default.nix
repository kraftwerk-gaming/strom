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

  saveLocations = [ "AppData/Roaming/Balatro" ];

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
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Balatro (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "balatro";
  };
}
