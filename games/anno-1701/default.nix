{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  src = fetchIpfs {
    cid = "QmajdrBZvqXLktKec6nrrVM7dPEufiXYToaUf6AUdzYoDG";
    fallbackUrl = "https://archive.org/download/CA-WINDOWS-Anno-1701-AD/Anno%201701%20-%20AD.7z";
    hash = "sha256-1dc1aLBnND/FGtA3CGwXTHjGEkxIuxH1YV7NL9mA8HY=";
    name = "anno-1701-ad.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anno-1701";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x "$src" -o/tmp/anno
    cp -r "/tmp/anno/Anno 1701 - AD"/* "$out"/
  '';

  runtime = "proton";
  # Anno1701AddOn.exe is the Gold/AD entry point (base game + Sunken Treasure addon).
  executable = "Anno1701AddOn.exe";

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
    description = "Anno 1701 + Sunken Treasure (Gold/AD, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anno-1701";
  };
}
