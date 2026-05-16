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
  # GOG Linux release of Baldur's Gate II: Enhanced Edition + DLC
  # (Throne of Bhaal, Reflections of Myth & Valor), Beamdog v2.6.6.0p,
  # from the Phoenix Games Lab collection. This tar.xz is the
  # pre-extracted mojosetup tree (.mojosetup/, docs/, game/, support/,
  # gameinfo). The game/ subtree contains BaldursGateII (a custom
  # Beamdog C++ build of the Infinity Engine) and chitin.key/data/lang
  # resources. Unlike BG1EE this archive does NOT bundle lib64/ —
  # BaldursGateII still NEEDs libssl.so.1.0.0 / libcrypto.so.1.0.0
  # (legacy OpenSSL 1.0 ABI which nixpkgs no longer carries), so we
  # pull those two .so files out of the BG1EE installer (same Beamdog
  # stack, same OpenSSL ABI) and stage them into a local lib64/.
  installer = fetchIpfs {
    cid = "QmY2spdmrnYVRyzezepfxtMjd5kdJe6fNv6EGE5eQpT2xc";
    fallbackUrl = "https://archive.org/download/baldurs-gate-ii-enhanced-edition-linux-gog-phoenix-games-lab/game-Baldurs_Gate_II_Enhanced_Edition_%2B_DLC_%28v2.6.6.0p%29_%5BLinux%2C_GOG%2C_Archive%2C_Fixed_Libs%5D.tar.xz";
    hash = "sha256-E3yGHvqdV5/sHM97tAfbdvNzI6J6/neWyWiB9s2LTNM=";
    name = "baldurs-gate-ii-enhanced-edition-2.6.6.0p.tar.xz";
  };

  # BG1EE installer reused only to harvest game/lib64/libssl.so.1.0.0
  # and game/lib64/libcrypto.so.1.0.0. Same Beamdog Infinity Engine
  # build, same legacy OpenSSL ABI. Keeping the fetchIpfs here means
  # ipfsSources will pin both tarballs for users who install BG2EE.
  bg1Installer = fetchIpfs {
    cid = "QmZ4jgzHSoB9uLEoFkKuktoAQfEY9B6kqVtGJWPvuAw3dB";
    fallbackUrl = "https://archive.org/download/baldurs-gate-enhanced-edition-linux-gog-phoenix-games-lab/game-Baldurs_Gate_Enhanced_Edition_%2B3_DLC_%28v2.6.6.0p%29_%5BLinux%2C_GOG%2C_Archive%2C_Fixed_Libs%5D.tar.xz";
    hash = "sha256-LWhvzleSQOiuushDMe/fxXg+oI1wPNdx4IN7lbRSb1g=";
    name = "baldurs-gate-enhanced-edition-2.6.6.0p.tar.xz";
  };

  gameData = stdenv.mkDerivation {
    pname = "baldurs-gate-ii-enhanced-edition-data";
    version = "2.6.6.0p";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      xz
      autoPatchelfHook
    ];

    # BaldursGateII NEEDs libopenal/libGL/libssl/libcrypto/libexpat/
    # libstdc++/libpthread/libc/libm. libssl/libcrypto come from the
    # BG1EE installer's bundled lib64; the rest come from the system.
    # autoPatchelf fixes the interpreter + NEEDED entries.
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
      # Harvest the legacy libssl/libcrypto from the BG1EE installer
      # (same Beamdog stack, same OpenSSL 1.0 ABI). Stage them into
      # game/lib64/ so the BG2EE tree matches the BG1EE layout that
      # our launcher expects.
      mkdir -p game/lib64
      tar -xJf ${bg1Installer} \
        --strip-components=2 -C game/lib64 \
        game/lib64/libssl.so.1.0.0 \
        game/lib64/libcrypto.so.1.0.0
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r game/. "$out"/
      # Drop GOG installer metadata / hashdb files; keep the engine,
      # data, lang, Manuals and the harvested lib64.
      rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb
      chmod +x "$out/BaldursGateII"

      # The shipped GOG start.sh sets cwd=game/ + LD_LIBRARY_PATH=./lib64
      # before exec'ing ./BaldursGateII. Recreate that as a top-level
      # launcher: BaldursGateII has no $ORIGIN RPATH so libssl/libcrypto
      # from lib64/ must come in via LD_LIBRARY_PATH. We prepend the
      # bundled dir to whatever mkGame's env block already provides.
      cat > "$out/baldurs-gate-ii-enhanced-edition" <<'EOF'
      #!/bin/sh
      here="$(dirname "$(readlink -f "$0")")"
      cd "$here"
      export LD_LIBRARY_PATH="$here/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec "./BaldursGateII" "$@"
      EOF
      chmod +x "$out/baldurs-gate-ii-enhanced-edition"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "baldurs-gate-ii-enhanced-edition";

  ipfsSources = [
    installer
    bg1Installer
  ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "baldurs-gate-ii-enhanced-edition";

  env = {
    # Beamdog's Infinity Engine build links libopenal/libGL/libexpat by
    # NEEDED, plus SDL2-style dlopens for X11/wayland/audio/dbus that
    # mirror what BG1EE / graveyard-keeper / shovel-knight need. Cover
    # the full set so SDL picks whatever the host provides.
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
    description = "Baldur's Gate II: Enhanced Edition + DLC (native Linux, Beamdog GOG v2.6.6.0p)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "baldurs-gate-ii-enhanced-edition";
  };
}
