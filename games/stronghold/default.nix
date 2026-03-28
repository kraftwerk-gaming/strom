{
  buildFHSEnv,
  fetchurl,
  innoextract,
  pkgsi686Linux,
  proton-ge-bin,
  runCommandLocal,
  writeShellScript,
}:

let
  proton = proton-ge-bin.steamcompattool;

  gameInstaller = fetchurl {
    url = "https://archive.org/download/setup_stronghold_hd_2.0.0.3/setup_stronghold_hd_2.0.0.3.exe";
    hash = "sha256-wV9zOe8d7JhzF7vbiz6QT5hysdVR4xSZ+L39/SVNwfM=";
    name = "setup_stronghold_hd.exe";
  };

  gameFiles =
    runCommandLocal "stronghold-data"
      {
        nativeBuildInputs = [ innoextract ];
      }
      ''
        mkdir -p "$out"
        innoextract -d "$out" ${gameInstaller}
        mv "$out/app"/* "$out"/
        rmdir "$out/app"
      '';

  wrapper = writeShellScript "stronghold-wrapper" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.strom/stronghold"
    COMPATDATA="$GAMEDIR/compatdata"
    mkdir -p "$GAMEDIR" "$COMPATDATA"

    # Recursively symlink game files, creating real directories
    link_tree() {
      local src="$1" dst="$2"
      mkdir -p "$dst"
      for f in "$src"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        if [ -d "$f" ]; then
          link_tree "$f" "$dst/$base"
        elif [ ! -e "$dst/$base" ] || [ -L "$dst/$base" ]; then
          ln -sf "$f" "$dst/$base"
        fi
      done
    }
    link_tree "${gameFiles}" "$GAMEDIR"

    # Make config files writable
    find "$GAMEDIR" -type l \( -name "*.cfg" -o -name "*.ini" -o -name "*.log" \) | while read -r f; do
      target="$(readlink "$f")"
      if [ -f "$target" ]; then
        rm "$f"
        cp "$target" "$f"
        chmod u+w "$f"
      fi
    done
    find "$GAMEDIR" -maxdepth 3 ! -writable -type f \( -name "*.cfg" -o -name "*.ini" -o -name "*.log" \) \
      -exec chmod u+w {} + 2>/dev/null || true

    # Ensure writable save directory
    mkdir -p "$GAMEDIR/Saves"

    export STEAM_COMPAT_DATA_PATH="$COMPATDATA"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
    export STEAM_COMPAT_APP_ID="0"
    export SteamAppId="0"
    export SteamGameId="0"
    export PROTON_NO_GAME_FIXES=1

    export LD_LIBRARY_PATH="/usr/lib32:/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    export DXVK_ASYNC=1
    export DXVK_STATE_CACHE_PATH="$GAMEDIR"
    export STAGING_WRITECOPY=1
    export WINE_LARGE_ADDRESS_AWARE=1

    cd "$GAMEDIR"

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
      python3 "${proton}/proton" waitforexitandrun "$GAMEDIR/Stronghold.exe"
  '';
in
buildFHSEnv {
  name = "stronghold";
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
    description = "Stronghold HD (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stronghold";
  };
}
