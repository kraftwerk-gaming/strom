{
  buildFHSEnv,
  callPackage,
  fetchurl,
  innoextract,
  pkgsi686Linux,
  proton-ge-bin,
  runCommandLocal,
  unzip,
  writeShellScript,
}:

let
  proton = proton-ge-bin.steamcompattool;
  sdl2-real = callPackage ./sdl2-real.nix { };

  gameArchive = fetchurl {
    url = "https://archive.org/download/legacy-of-kain-soul-reaver-gog/Legacy%20of%20Kain%20Soul%20Reaver%20%5BGOG%5D.zip";
    hash = "sha256-RWC9JCqwRTqAOrMzKz70o3RrFaKsrkNQrHwc3yq5FDI=";
    name = "soul-reaver-gog.zip";
  };

  # dxwrapper - DirectDraw to Direct3D9 wrapper, fixes rendering and input
  dxwrapper = fetchurl {
    url = "https://github.com/elishacloud/dxwrapper/releases/download/v1.6.8300.25/dx7.games.zip";
    hash = "sha256-JwAc533qpi0tK7ilVX7FS0X9RI3VuIBI+si93wRHF54=";
    name = "dxwrapper.zip";
  };

  gameFiles =
    runCommandLocal "soul-reaver-data"
      {
        nativeBuildInputs = [
          innoextract
          unzip
        ];
      }
      ''
        mkdir -p "$out"
        unzip -j ${gameArchive} "*/setup_legacy_of_kain_soul_reaver_*.exe" -d /tmp/sr
        innoextract -d /tmp/sr-extract /tmp/sr/setup_legacy_of_kain_soul_reaver_*.exe
        mv /tmp/sr-extract/app/* "$out"/

        # Add dxwrapper (DirectDraw 7 -> Direct3D 9 conversion)
        unzip -o ${dxwrapper} -d "$out"/

        # Configure dxwrapper
        sed -i \
          -e 's/Dinputto8                  = 0/Dinputto8                  = 1/' \
          -e 's/DdrawLimitDisplayModeCount = 0/DdrawLimitDisplayModeCount = 1/' \
          "$out/dxwrapper.ini"

        # Create dinput.dll wrapper (copy of ddraw.dll so dxwrapper intercepts DInput)
        cp "$out/ddraw.dll" "$out/dinput.dll"
      '';

  wrapper = writeShellScript "soul-reaver-wrapper" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.strom/soul-reaver"
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

    export STEAM_COMPAT_DATA_PATH="$COMPATDATA"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
    export STEAM_COMPAT_APP_ID="0"
    export SteamAppId="0"
    export SteamGameId="0"
    # Override .arg to select hardware D3D device
    rm -f "$GAMEDIR/kain2.arg"
    echo "under 0 -mainmenu -voice -inspectral" > "$GAMEDIR/kain2.arg"

    export PROTON_NO_GAME_FIXES=1
    export STEAM_COMPAT_CONFIG=sdlinput
    export WINEDLLOVERRIDES="ddraw,dinput=n,b"
    export LD_LIBRARY_PATH="/usr/lib32:/usr/lib:/usr/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    cd "$GAMEDIR"

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland -- \
      python3 "${proton}/proton" waitforexitandrun "$GAMEDIR/kain2.exe"
  '';
in
buildFHSEnv {
  name = "soul-reaver";
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
    description = "Legacy of Kain: Soul Reaver (GOG, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "soul-reaver";
  };
}
