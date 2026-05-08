{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  gnutar,
  autoPatchelfHook,
  stdenv,
}:

let
  # Gish 1.6.4 Turbo Edition (the final 2025 community-recompiled release
  # by Cryptic Sea / Chronic Logic, originally 2004). This zip wraps a
  # single tar.gz with the native Linux build (gish_64 + gish_32 ELFs and
  # the data tree). Released by Chronic Logic for free in the final
  # archive of the original Gish.
  installer = fetchIpfs {
    cid = "QmWBgZmJ4AAKAZd6mfGkvDRaREe6bLTMLcfc7VnXEohLuH";
    fallbackUrl = "https://archive.org/download/gish-1.6.4-turbo-edition/Gish%201.6.4%20Turbo%20Edition%20Linux.zip";
    hash = "sha256-jYrTY5s9iGjMQnD6HKT8g1/V8Y4wMsYYfsvwbIm6gEA=";
    name = "gish-1.6.4-turbo-edition-linux.zip";
  };

  gameData = stdenv.mkDerivation {
    pname = "gish-data";
    version = "1.6.4";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      gnutar
      autoPatchelfHook
    ];

    # gish_64 dynamically links libSDL-1.2, libGL, libopenal, libvorbisfile,
    # libX11, libm, libc — all loaded as NEEDED, no dlopen surprises.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      SDL
      libGL
      openal
      libvorbis
      xorg.libX11
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer}
      tar -xzf "Gish 1.6.4 Turbo Edition Linux/gish_1_6.tar.gz"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r gish/. "$out"/
      chmod +x "$out/gish_64"
      # Drop the 32-bit binary; we only ship x86_64.
      rm -f "$out/gish_32"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gish";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "gish_64";

  env = {
    # The bundled libopenal pulls in libpulse/libasound by bare name at
    # runtime; SDL 1.2 also dlopens its X11/audio backends. Provide them
    # all on LD_LIBRARY_PATH.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        SDL
        libGL
        openal
        libvorbis
        libpulseaudio
        alsa-lib
        xorg.libX11
        xorg.libXext
      ]
    );
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Gish (2004 Cryptic Sea / Chronic Logic, native Linux 1.6.4 Turbo Edition)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "gish";
  };
}
