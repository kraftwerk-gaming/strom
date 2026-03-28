{
  buildFHSEnv,
  fetchurl,
  p7zip,
  pkgsi686Linux,
  proton-ge-bin,
  runCommandLocal,
  writeShellScript,
}:

let
  proton = proton-ge-bin.steamcompattool;

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
      '';

  wrapper = writeShellScript "nfs-underground-2-wrapper" ''
        set -euo pipefail

        GAMEDIR="''${HOME:-.}/.strom/nfs-underground-2"
        COMPATDATA="$GAMEDIR/compatdata"
        mkdir -p "$GAMEDIR" "$COMPATDATA"

        # Recursively symlink game files, creating real directories
        # so the game can write alongside read-only store files
        link_tree() {
          local src="$1" dst="$2"
          mkdir -p "$dst"
          for f in "$src"/*; do
            base="$(basename "$f")"
            if [ -d "$f" ]; then
              link_tree "$f" "$dst/$base"
            elif [ ! -e "$dst/$base" ] || [ -L "$dst/$base" ]; then
              ln -sf "$f" "$dst/$base"
            fi
          done
        }
        link_tree "${gameFiles}" "$GAMEDIR"

        # Replace symlinks to config files with writable copies
        # (ReShade and other mods need to write to these)
        find "$GAMEDIR" -type l \( -name "*.ini" -o -name "*.cfg" -o -name "*.log" -o -name "*.json" \) | while read -r f; do
          target="$(readlink "$f")"
          if [ -f "$target" ]; then
            rm "$f"
            cp "$target" "$f"
            chmod u+w "$f"
          fi
        done

        # Also ensure any previously copied read-only files become writable
        find "$GAMEDIR" -maxdepth 3 ! -writable -type f \( -name "*.ini" -o -name "*.cfg" -o -name "*.log" -o -name "*.json" \) -exec chmod u+w {} + 2>/dev/null || true

        # Ensure writable save directories
        mkdir -p "$GAMEDIR/SAVE"
        rm -f "$GAMEDIR/SAVEGAMES/NFS Underground 2/*" 2>/dev/null || true

        export STEAM_COMPAT_DATA_PATH="$COMPATDATA"
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
        export STEAM_COMPAT_APP_ID="0"

        # Libraries for Wine/Proton
        export LD_LIBRARY_PATH="/usr/lib32:/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

        # DXVK config
        cat > "$GAMEDIR/dxvk.conf" <<DXVKCONF
        d3d9.floatEmulation = strict
        d3d9.memoryTrackTest = True
    DXVKCONF
        export DXVK_CONFIG_FILE="$GAMEDIR/dxvk.conf"
        export DXVK_ASYNC=1
        export DXVK_STATE_CACHE_PATH="$GAMEDIR"
        export STAGING_WRITECOPY=1
        export WINE_LARGE_ADDRESS_AWARE=1

        cd "$GAMEDIR"

        # Find the game executable
        EXE=""
        for candidate in speed2.exe SPEED2.EXE Speed2.exe "speed 2.exe"; do
          if [ -f "$GAMEDIR/$candidate" ]; then
            EXE="$candidate"
            break
          fi
        done

        if [ -z "$EXE" ]; then
          echo "Could not find game executable. Files in game dir:"
          ls -la "$GAMEDIR"/*.exe 2>/dev/null || echo "No .exe files found"
          exit 1
        fi

        exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
          python3 "${proton}/proton" waitforexitandrun "$GAMEDIR/$EXE"
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
    # Vulkan/OpenGL drivers
    pkgs.mesa
    pkgs.vulkan-loader
    pkgs.libGL
    # X11 libraries
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
    # Audio
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.openal
    # 32-bit libraries
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
    description = "Need for Speed: Underground 2 (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "nfs-underground-2";
  };
}
