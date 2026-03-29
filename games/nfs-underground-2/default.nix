{
  buildFHSEnv,
  callPackage,
  fetchurl,
  p7zip,
  pkgsi686Linux,
  proton-ge-bin,
  runCommandLocal,
  writeShellScript,
}:

let
  proton = proton-ge-bin.steamcompattool;
  sdl2-real = callPackage ../../lib/sdl2-real.nix { };

  gameArchive = fetchurl {
    url = "https://archive.org/download/NFSU2Stable/Need%20for%20Speed%20Underground%202.7z";
    hash = "sha256-aC+1gcJLFay2jWTDBOXZSL3tIxaBoDHV1amtl82XBlA=";
    name = "nfsu2.7z";
  };

  gameFiles =
    runCommandLocal "nfsu2-data"
      {
        nativeBuildInputs = [ p7zip ];
      }
      ''
        mkdir -p "$out"
        7z x ${gameArchive} -o"$out"

        # Find the game directory (may be nested)
        if [ -d "$out/Need for Speed Underground 2" ]; then
          mv "$out/Need for Speed Underground 2"/* "$out"/
          rmdir "$out/Need for Speed Underground 2"
        fi

        # Remove ALL mods - keep only dinput8.dll (ASI loader + no-CD)
        rm -f "$out/SCRIPTS/"*.asi
        rm -f "$out/SCRIPTS/ReShade"*
        rm -rf "$out/SCRIPTS/Shaders" "$out/SCRIPTS/Textures"
        rm -rf "$out/TexturePacks"
      '';

  wrapper = writeShellScript "nfs-underground-2-wrapper" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.strom/nfs-underground-2"
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

    # Copy files that the game needs to write to (replace symlinks)
    for f in "$GAMEDIR"/*.ini "$GAMEDIR"/*.cfg "$GAMEDIR"/*.log "$GAMEDIR"/*.json \
             "$GAMEDIR"/*.016 "$GAMEDIR"/*.256; do
      [ -L "$f" ] || continue
      target="$(readlink "$f")"
      if [ -f "$target" ]; then
        rm "$f"
        cp "$target" "$f"
        chmod u+w "$f"
      fi
    done

    # Ensure config files in subdirectories are writable too
    find "$GAMEDIR" -maxdepth 3 -type l \( -name "*.ini" -o -name "*.cfg" -o -name "*.json" \) | while read -r f; do
      target="$(readlink "$f")"
      if [ -f "$target" ]; then
        rm "$f"
        cp "$target" "$f"
        chmod u+w "$f"
      fi
    done

    export STEAM_COMPAT_DATA_PATH="$COMPATDATA"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
    export STEAM_COMPAT_APP_ID="0"
    export STEAM_COMPAT_CONFIG=sdlinput
    export LD_LIBRARY_PATH="/usr/lib32:/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export DXVK_ASYNC=1
    export DXVK_FRAME_RATE=60
    export PULSE_LATENCY_MSEC=60
    export STAGING_WRITECOPY=1
    export WINE_LARGE_ADDRESS_AWARE=1

    cd "$GAMEDIR"

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
      python3 "${proton}/proton" waitforexitandrun "$GAMEDIR/SPEED2.EXE"
  '';
in
buildFHSEnv {
  name = "nfs-underground-2";
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
    pkgs.systemd
    sdl2-real
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

  extraBwrapArgs = [
    "--ro-bind /sys /sys"
    "--bind /run /run"
  ];

  meta = {
    description = "Need for Speed: Underground 2 (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "nfs-underground-2";
  };
}
