{
  callPackage,
  lib,
  pkgs,
  fetchurl,
  p7zip,
  wineWow64Packages,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };
  wine = wineWow64Packages.stable;
in
mkGame {
  name = "untitled-goose-game";

  src = fetchurl {
    url = "https://archive.org/download/untitled-goose-game-portable-hoang-long/Untitled_Goose_Game_Portable%5BHoangLong%5D.7z";
    hash = "sha256-CAcpFF28cM/Gu032tHL9SdBHHAXCWx2w6ycqL8HEG+Y=";
    name = "goose.7z";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x $src -o/tmp/goose
    mv /tmp/goose/DATA/* "$out"/
  '';

  copyGlobs = [ ];

  runtime = "custom";

  targetPkgs = p: [
    p.freetype
    p.glibc
    p.gamescope
    wine
    p.mesa
    p.vulkan-loader
    p.libGL
    p.libx11
    p.libxext
    p.libxcb
    p.libxcursor
    p.libxrandr
    p.libxi
    p.libxfixes
    p.libxrender
    p.libxcomposite
    p.libxinerama
    p.libxxf86vm
    p.libxau
    p.libxdmcp
    p.alsa-lib
    p.libpulseaudio
    p.openal
  ];

  extraBwrapArgs = [
    "--ro-bind /sys /sys"
    "--bind /run /run"
  ];

  env = {
    WINEDLLOVERRIDES = "mscoree=d;mshtml=d";
  };

  runScript = ''
    export WINEPREFIX="$GAMEDIR/wine"

    if [ ! -d "$WINEPREFIX" ]; then
      wineboot --init 2>/dev/null
      wineserver -k 2>/dev/null
    fi

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
      sh -c 'wine "$0" "$@"; wineserver -k' "$GAMEDIR/Untitled.exe"
  '';

  meta = {
    description = "Untitled Goose Game (via Wine and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "untitled-goose-game";
  };
}
