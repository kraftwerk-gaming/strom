{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Pre-installed Gold Edition (base game + Venice expansion), No-CD patched.
  src = fetchIpfs {
    cid = "QmX4XBLMuKUgZn1G18igyJPLwcVASKTH7V9YJ6Kf78Stwz";
    fallbackUrl = "https://archive.org/download/CA-WINDOWS-Anno-1404/Anno%201404%20-%20Gold%20Edition.7z";
    hash = "sha256-DgOK4l6OLnoO0Pu1WY7iPjoW+lyAFWRYRdPFZa5Iw44=";
    name = "anno-1404-gold-edition.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anno-1404";

  ipfsSources = [ src ];

  src = pkgs.runCommandLocal "anno-1404-data" { nativeBuildInputs = [ p7zip ]; } ''
    mkdir -p "$out"
    7z x -o"$out" ${src}
    mv "$out/Anno 1404 - Gold Edition/"* "$out/"
    rmdir "$out/Anno 1404 - Gold Edition"
  '';

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "proton";
  # Addon.exe is the Gold Edition entry point (base game + Venice expansion).
  executable = "Addon.exe";

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
    description = "Anno 1404 Gold Edition (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anno-1404";
  };
}
