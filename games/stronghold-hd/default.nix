{
  lib,
  pkgs,
  fetchurl,
  innoextract,
  pkgsi686Linux,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };
in
mkGame {
  name = "stronghold-hd";

  src = fetchurl {
    url = "https://archive.org/download/setup_stronghold_hd_2.0.0.3/setup_stronghold_hd_2.0.0.3.exe";
    hash = "sha256-wV9zOe8d7JhzF7vbiz6QT5hysdVR4xSZ+L39/SVNwfM=";
    name = "setup_stronghold_hd.exe";
  };

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract -d "$out" $src
    mv "$out/app"/* "$out"/
    rmdir "$out/app"
  '';

  runtime = "proton";
  executable = "Stronghold.exe";
  gamescopeArgs = "-W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland";

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
    pkgs.python3
    pkgs.mesa
    pkgs.vulkan-loader
    pkgs.libGL
    pkgs.libx11
    pkgs.libxext
    pkgs.libxcb
    pkgs.libxcursor
    pkgs.libxrandr
    pkgs.libxi
    pkgs.libxfixes
    pkgs.libxrender
    pkgs.libxcomposite
    pkgs.libxinerama
    pkgs.libxxf86vm
    pkgs.libxau
    pkgs.libxdmcp
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.openal
    pkgsi686Linux.freetype
    pkgsi686Linux.glibc
    pkgsi686Linux.glib
    pkgsi686Linux.libx11
    pkgsi686Linux.libxext
    pkgsi686Linux.libxcb
    pkgsi686Linux.libxcursor
    pkgsi686Linux.libxrandr
    pkgsi686Linux.libxi
    pkgsi686Linux.libxfixes
    pkgsi686Linux.libxrender
    pkgsi686Linux.libxcomposite
    pkgsi686Linux.libxinerama
    pkgsi686Linux.libxxf86vm
    pkgsi686Linux.libxau
    pkgsi686Linux.libxdmcp
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Stronghold HD (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stronghold-hd";
  };
}
