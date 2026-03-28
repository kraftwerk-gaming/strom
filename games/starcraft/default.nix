{
  buildFHSEnv,
  fetchurl,
  pkgsi686Linux,
  proton-ge-bin,
  runCommandLocal,
  unzip,
  writeShellScript,
}:

let
  proton = proton-ge-bin.steamcompattool;

  gameArchive = fetchurl {
    url = "https://archive.org/download/sc-classic-installer_202311/StarCraft%20Portable.zip";
    hash = "sha256-LotKRHxNGrDSO2afcqwkwxdwzkjS7saSZcF6a/By9zU=";
    name = "starcraft-portable.zip";
  };

  gameFiles =
    runCommandLocal "starcraft-data"
      {
        nativeBuildInputs = [ unzip ];
      }
      ''
        mkdir -p "$out"
        unzip -o ${gameArchive} -d /tmp/sc
        mv /tmp/sc/Starcraft\ Brood\ War/* "$out"/

        # Rename the oddly named exe
        mv "$out/StarCraft ( Click here ).exe" "$out/StarCraft.exe"

        # Remove third-party mods and tools
        rm -rf "$out/Backup" "$out/APM_check" "$out/Record"
        rm -f "$out/unins000.exe" "$out/unins000.dat"
        rm -f "$out/Chaoslauncher.exe" "$out/Chaosupdater.exe" "$out/InsectLoader.exe"
        rm -f "$out/Launcher.exe" "$out/Res.exe" "$out/StarcraftResolutionHack.exe"
        rm -f "$out"/*.bwl "$out"/*.icc
        rm -f "$out/RepAnalyser.dll" "$out/ResolutionHackDemo.dll"
        rm -f "$out/EditLocal.dll" "$out/psapi.dll" "$out/w3lh.dll"
        rm -f "$out/alert.wav" "$out/Attack.ani" "$out/StarCraft.ani"
        rm -f "$out/scfix.vbs" "$out/SafeMode.bat" "$out/SETUP.EXE"
        rm -f "$out"/*.url "$out"/*.log "$out"/*.ini
        rm -f "$out/install.ex_" "$out/patch_rt.mp_"
      '';

  wrapper = writeShellScript "starcraft-wrapper" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.starcraft"
    COMPATDATA="$GAMEDIR/compatdata"
    mkdir -p "$GAMEDIR" "$COMPATDATA"

    # Copy game files (StarCraft can't handle symlinks)
    if [ ! -f "$GAMEDIR/StarCraft.exe" ]; then
      cp -r "${gameFiles}"/. "$GAMEDIR/"
      chmod -R u+w "$GAMEDIR"
    fi

    mkdir -p "$GAMEDIR/maps" "$GAMEDIR/save"

    export STEAM_COMPAT_DATA_PATH="$COMPATDATA"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
    export STEAM_COMPAT_APP_ID="0"
    export SteamAppId="0"
    export SteamGameId="0"
    export PROTON_NO_GAME_FIXES=1
    export LD_LIBRARY_PATH="/usr/lib32:/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    cd "$GAMEDIR"

    exec gamescope -W 1920 -H 1080 -w 640 -h 480 -r 60 --immediate-flips --expose-wayland -- \
      python3 "${proton}/proton" waitforexitandrun "$GAMEDIR/StarCraft.exe"
  '';
in
buildFHSEnv {
  name = "starcraft";
  runScript = wrapper;

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
    description = "StarCraft + Brood War (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "starcraft";
  };
}
