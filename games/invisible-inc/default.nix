{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  stdenv,
}:

let
  # Invisible, Inc. + DLC (Klei 2015, Moai/Lua engine), GOG v281021 build
  # v22858, native Linux 64-bit. Archive.org item "invisible-inc-gog-linux"
  # is a tar bundling the base-game GOG .sh installer
  # (invisible_inc_en_281021_22858.sh, 892 MB) plus the Contingency Plan
  # DLC .sh (26 MB). The base-game .sh is a Makeself/mojosetup archive
  # whose payload is an appended zip (game tree at data/noarch/game/);
  # `unzip` extracts without running the interactive installer.
  installer = fetchIpfs {
    cid = "QmeiVKXeDFitaCqqHzSvmV6cgGA7aVU6PGXxo3Go3AJbXb";
    fallbackUrl = "https://archive.org/download/invisible-inc-gog-linux/Invisible_Inc._+DLC_(v281021)_%5BLinux,_GOG,_v22858%5D.tar";
    hash = "sha256-+Syh8t6YYXm62e/Mzse2zZHm9AVzGTT7ysLOgw/kKyM=";
    name = "invisible-inc-linux-gog-v281021.tar";
  };

  gameData = stdenv.mkDerivation {
    pname = "invisible-inc-data";
    version = "281021";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      pkgs.gnutar
      autoPatchelfHook
    ];

    # InvisibleInc64 is a Moai-engine ELF. NEEDED entries:
    # libGL.so.1, libSDL2-2.0.so.0, libfmodex64.so, libfmodevent64.so,
    # libstdc++.so.6, libgcc_s.so.1. The SDL2/fmod/steam_api libs are
    # bundled in lib64/ (moved to lib/ by the fixup phase), so
    # autoPatchelfHook resolves them from $out/lib. libGL needs a
    # build-time stub to satisfy the NEEDED entry.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
    ];

    buildPhase = ''
      runHook preBuild
      tar xf ${installer} invisible_inc_en_281021_22858.sh
      unzip -q invisible_inc_en_281021_22858.sh || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/InvisibleInc64"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "invisible-inc";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "InvisibleInc64";

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        libpulseaudio
        alsa-lib
        udev
        libx11
        libxext
        libxcursor
        libxrandr
        libxi
        libxinerama
        libxscrnsaver
        libxcb
      ]
    );
  };

  # Klei's Moai engine saves to ~/.klei/InvisibleInc/ on Linux.
  saveLocations = [ ".klei/InvisibleInc" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Invisible, Inc. (Klei 2015, native Linux, GOG v281021)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "invisible-inc";
  };
}
