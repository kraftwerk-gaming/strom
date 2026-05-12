{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gnutar,
  xz,
  autoPatchelfHook,
  stdenv,
}:

let
  # GOG Linux release of Baldur's Gate: Enhanced Edition + 3 DLC
  # (Siege of Dragonspear etc.), Beamdog v2.6.6.0p, fixed-libs rebuild
  # from the Phoenix Games Lab collection. This tar.xz is the
  # pre-extracted mojosetup tree (.mojosetup/, docs/, game/, support/,
  # start.sh, gameinfo). The game/ subtree contains BaldursGate (a
  # custom Beamdog C++ build of the Infinity Engine), bundled lib64/
  # libssl+libcrypto, and the chitin.key/data/override resources.
  # start.sh sets cwd=game/ and LD_LIBRARY_PATH=./lib64 before exec'ing
  # ./BaldursGate; we mirror that in a tiny launcher script.
  installer = fetchIpfs {
    cid = "QmZ4jgzHSoB9uLEoFkKuktoAQfEY9B6kqVtGJWPvuAw3dB";
    fallbackUrl = "https://archive.org/download/baldurs-gate-enhanced-edition-linux-gog-phoenix-games-lab/game-Baldurs_Gate_Enhanced_Edition_%2B3_DLC_%28v2.6.6.0p%29_%5BLinux%2C_GOG%2C_Archive%2C_Fixed_Libs%5D.tar.xz";
    hash = "sha256-LWhvzleSQOiuushDMe/fxXg+oI1wPNdx4IN7lbRSb1g=";
    name = "baldurs-gate-enhanced-edition-2.6.6.0p.tar.xz";
  };

  gameData = stdenv.mkDerivation {
    pname = "baldurs-gate-enhanced-edition-data";
    version = "2.6.6.0p";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      xz
      autoPatchelfHook
    ];

    # BaldursGate NEEDs libopenal/libGL/libssl/libcrypto/libexpat/
    # libstdc++/libpthread/libc/libm. libssl/libcrypto ship in
    # game/lib64; the rest come from the system. autoPatchelf fixes the
    # interpreter + NEEDED entries.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      openal
      libGL
      expat
    ];

    buildPhase = ''
      runHook preBuild
      tar -xJf ${installer}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r game/. "$out"/
      # Drop GOG installer metadata / hashdb files; keep the engine,
      # data, lang, movies, music, override, portraits, scripts and
      # the bundled lib64.
      rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb
      chmod +x "$out/BaldursGate"

      # The shipped GOG start.sh sets cwd=game/ + LD_LIBRARY_PATH=./lib64
      # before exec'ing ./BaldursGate. Recreate that as a top-level
      # launcher: BaldursGate has no $ORIGIN RPATH so libssl/libcrypto
      # from lib64/ must come in via LD_LIBRARY_PATH. We prepend the
      # bundled dir to whatever mkGame's env block already provides.
      cat > "$out/baldurs-gate-enhanced-edition" <<'EOF'
      #!/bin/sh
      here="$(dirname "$(readlink -f "$0")")"
      cd "$here"
      export LD_LIBRARY_PATH="$here/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec "./BaldursGate" "$@"
      EOF
      chmod +x "$out/baldurs-gate-enhanced-edition"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "baldurs-gate-enhanced-edition";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "baldurs-gate-enhanced-edition";

  env = {
    # Beamdog's Infinity Engine build links libopenal/libGL/libexpat by
    # NEEDED, plus SDL2-style dlopens for X11/wayland/audio/dbus that
    # mirror what graveyard-keeper / shovel-knight need. Cover the full
    # set so SDL picks whatever the host provides.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        vulkan-loader
        openal
        libpulseaudio
        alsa-lib
        dbus
        expat
        wayland
        libxkbcommon
        udev
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
      ]
    );
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Baldur's Gate: Enhanced Edition + 3 DLC (native Linux, Beamdog GOG v2.6.6.0p, fixed libs)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "baldurs-gate-enhanced-edition";
  };
}
