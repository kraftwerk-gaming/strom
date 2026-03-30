{
  buildFHSEnv,
  callPackage,
  fetchurl,
  p7zip,
  pkgsi686Linux,
  proton-ge-bin,
  python3,
  runCommandLocal,
  wineWow64Packages,
  writeShellScript,
  xvfb-run,
}:

let
  proton = proton-ge-bin.steamcompattool;
  sdl2-real = callPackage ../../lib/sdl2-real.nix { };
  wine = wineWow64Packages.stable;

  gameISO = fetchurl {
    url = "https://archive.org/download/europa-1400-gold-edition/E1400_Gold_UK.iso";
    hash = "sha256-cZmqwy++R9ei19prp5qCZiJDeYPNHole/NugLOsE/Cs=";
    name = "europa1400gold.iso";
  };

  # Extract ISO and run the Wise installer with Wine to get game files
  gameFiles =
    runCommandLocal "die-gilde-data"
      {
        nativeBuildInputs = [
          p7zip
          wine
          xvfb-run
        ];
      }
      ''
        # Extract ISO
        mkdir -p /tmp/iso
        7z x ${gameISO} -o/tmp/iso

        # Run the Wise installer silently with Wine
        export WINEPREFIX=/tmp/wineprefix
        export WINEDLLOVERRIDES="mscoree,mshtml="
        export WINEDEBUG=-all
        mkdir -p "$WINEPREFIX"

        xvfb-run -a wine /tmp/iso/setup.exe /S

        # Copy installed game files to output
        cp -r "$WINEPREFIX/drive_c/Program Files (x86)/JoWooD/Europa 1400 - Gold Edition" "$out"
      '';

  wrapper = writeShellScript "die-gilde-wrapper" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.strom/die-gilde"
    COMPATDATA="$GAMEDIR/compatdata"
    mkdir -p "$GAMEDIR" "$COMPATDATA"

    # Symlink game files, creating real directories
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

    # Make writable files the game needs to modify
    for f in "$GAMEDIR"/*.ini "$GAMEDIR"/*.cfg "$GAMEDIR"/*.log; do
      [ -L "$f" ] || continue
      target="$(readlink "$f")"
      if [ -f "$target" ]; then
        rm "$f"
        cp "$target" "$f"
        chmod u+w "$f"
      fi
    done

    export STEAM_COMPAT_DATA_PATH="$COMPATDATA/0"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
    mkdir -p "$COMPATDATA/0"
    export STEAM_COMPAT_APP_ID="0"
    export PROTON_NO_PROTONFIXES=1
    export PROTON_USE_WINED3D=1
    export PULSE_LATENCY_MSEC=60

    # Ensure 32-bit libs are findable by wine
    export LD_LIBRARY_PATH="/usr/lib32:/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"



    cd "$GAMEDIR"
    # Set Wine virtual desktop to avoid DirectDraw display issues
    export WINE_VD=1024x768

    exec gamescope -W 1920 -H 1080 -w 1024 -h 768 --expose-wayland -- \
      python3 "${proton}/proton" waitforexitandrun "$GAMEDIR/Europa1400Gold.exe"
  '';
in
buildFHSEnv {
  name = "die-gilde";
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
    description = "Europa 1400: The Guild - Gold Edition (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "die-gilde";
  };
}
