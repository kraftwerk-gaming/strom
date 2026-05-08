{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  stdenv,
  glew,
}:

let
  # GOG Linux release of Hotline Miami 2: Wrong Number (v07.12.2017
  # build 16977). The .sh is a mojosetup self-extracting installer
  # (shell-script header + zip), so unzip handles it directly. The
  # 64-bit binary is HotlineMiami2; lib/ holds the bundled
  # libGLEW.so.1.10, libSDL2 and libfmod.so.7 it links against.
  installer = fetchIpfs {
    cid = "QmZBHY3bgwaquhviCuUsfBu6g6JUq1wV2JovmZMoXfwihL";
    fallbackUrl = "https://archive.org/download/hotline-miami-2-wrong-number-linux-gog-phoenix-games-lab/hotline_miami_2_wrong_number_en_07_12_2017_16977.sh";
    hash = "sha256-UsQZXX7Umow9vhMck1m2s1Lxk7CqGHMV2xiGo0Vds5s=";
    name = "hotline-miami-2-wrong-number-linux-gog-2017-12-07.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "hotline-miami-2-data";
    version = "2017-12-07";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      glew
      SDL2
      alsa-lib
      libpulseaudio
      xorg.libX11
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      unzip -q ${installer} 'data/noarch/game/HotlineMiami2' \
                            'data/noarch/game/lib/*' \
                            'data/noarch/game/gamecontrollerdb.txt' \
                            'data/noarch/game/hlm2_*.wad' || true
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/HotlineMiami2"
      # Wrap the binary so the bundled libSDL2/libGLEW/libfmod in lib/
      # are LD_LIBRARY_PATH-visible only to the game process, not to
      # gamescope. Mirrors the carrion approach.
      mv "$out/HotlineMiami2" "$out/HotlineMiami2-bin"
      cat > "$out/HotlineMiami2" <<'EOF'
      #!/bin/sh
      here="$(dirname "$0")"
      exec env LD_LIBRARY_PATH="$here/lib" "$here/HotlineMiami2-bin" "$@"
      EOF
      chmod +x "$out/HotlineMiami2"
      runHook postInstall
    '';

    # autoPatchelf scans buildInputs by default. The bundled libs in
    # $out/lib (libSDL2-2.0.so.0, libGLEW.so.1.10, libfmod.so.7) need
    # the same treatment so they resolve each other and so the main
    # binary's NEEDED entries find them. Register the path in preFixup
    # before auto-patchelf walks ELFs.
    preFixup = ''
      addAutoPatchelfSearchPath "$out/lib"
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hotline-miami-2-wrong-number";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "HotlineMiami2";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "--expose-wayland" = true;
      # Game uses absolute mouse mode incorrectly under gamescope —
      # cursor sticks in the top-left corner without forced grab.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Hotline Miami 2: Wrong Number (native Linux, GOG v2017-12-07 build 16977)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hotline-miami-2-wrong-number";
  };
}
