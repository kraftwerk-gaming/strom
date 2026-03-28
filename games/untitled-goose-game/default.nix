{
  buildFHSEnv,
  fetchurl,
  p7zip,
  runCommandLocal,
  wineWow64Packages,
  writeShellScript,
}:

let
  wine = wineWow64Packages.stable;

  gameArchive = fetchurl {
    url = "https://archive.org/download/untitled-goose-game-portable-hoang-long/Untitled_Goose_Game_Portable%5BHoangLong%5D.7z";
    hash = "sha256-CAcpFF28cM/Gu032tHL9SdBHHAXCWx2w6ycqL8HEG+Y=";
    name = "goose.7z";
  };

  gameFiles =
    runCommandLocal "goose-data"
      {
        nativeBuildInputs = [ p7zip ];
      }
      ''
        mkdir -p "$out"
        7z x ${gameArchive} -o/tmp/goose
        mv /tmp/goose/DATA/* "$out"/
      '';

  wrapper = writeShellScript "untitled-goose-game-wrapper" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.untitled-goose-game"
    mkdir -p "$GAMEDIR"

    # Copy game files (Unity games need writable directory)
    if [ ! -f "$GAMEDIR/Untitled.exe" ]; then
      cp -r "${gameFiles}"/. "$GAMEDIR/"
      chmod -R u+w "$GAMEDIR"
    fi

    export WINEPREFIX="$GAMEDIR/wine"
    export WINEDLLOVERRIDES="mscoree=d;mshtml=d"

    if [ ! -d "$WINEPREFIX" ]; then
      wineboot --init 2>/dev/null || true
      wineserver -k 2>/dev/null || true
    fi

    cd "$GAMEDIR"

    gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
      sh -c 'wine "$0" "$@"; wineserver -k' "$GAMEDIR/Untitled.exe"
  '';
in
buildFHSEnv {
  name = "untitled-goose-game";
  runScript = wrapper;

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
    wine
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
  ];

  extraBwrapArgs = [
    "--ro-bind /sys /sys"
    "--bind /run /run"
  ];

  meta = {
    description = "Untitled Goose Game (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "untitled-goose-game";
  };
}
