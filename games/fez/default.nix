{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  patchelf,
  zlib,
  stdenv,
  libGL,
  libX11,
  libXext,
  libXcursor,
  libXi,
  libXrandr,
  libXfixes,
  libXrender,
  libxcb,
  libpulseaudio,
  alsa-lib,
  libxkbcommon,
}:

let
  # GOG Linux installer (Makeself + mojosetup) for FEZ, version 2.1.0.4.
  installer = fetchIpfs {
    cid = "QmWbKaPKumQeNjRKEzxA1gSceAjATiFQyznPz4Ne4JRVHH";
    fallbackUrl = "https://archive.org/download/fez-linux-gog-phoenix-games-lab/gog_fez_2.1.0.4.sh";
    hash = "sha256-tKpIMX894t2K9Oas4XUbHEFQu07GfL6aRAXqix15/UU=";
    name = "gog_fez_2.1.0.4.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "fez-data";
    version = "2.1.0.4";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      patchelf
    ];

    buildPhase = ''
      runHook preBuild
      # The GOG installer is a Makeself archive containing a gzip header and
      # a zip payload. unzip finds the zip automatically, skipping the preamble.
      # unzip exits 1 on the extra-bytes warning even when extraction succeeds.
      unzip -q ${installer} "data/noarch/game/*" || [ $? -eq 1 ]
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/FEZ.bin.x86_64" "$out/FEZ.bin.x86"

      # Bundled libs in lib64/ need $ORIGIN in rpath so they find each other
      # (libvorbisfile -> libvorbis -> libogg). The main binary already has
      # $ORIGIN/lib64 rpath. libMonoPosixHelper.so needs libz.so.1 from zlib.
      for lib in "$out"/lib64/*.so*; do
        patchelf --set-rpath "\$ORIGIN:${
          lib.makeLibraryPath [
            zlib
            stdenv.cc.cc.lib
          ]
        }" "$lib"
      done

      # Patch the interpreter of the main binary so it finds ld-linux on NixOS.
      patchelf --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" "$out/FEZ.bin.x86_64"

      # MonoKickstart DllImport searches libs relative to the exe directory
      # (not lib64/), so symlink bundled libs into the game root.
      for lib in "$out"/lib64/*.so*; do
        ln -sf "lib64/$(basename "$lib")" "$out/$(basename "$lib")"
      done

      runHook postInstall
    '';

    dontStrip = true;
    dontMoveLib64 = true;
    dontPatchELF = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "fez";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "FEZ.bin.x86_64";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1280;
    nested-height = 720;
    flags."--expose-wayland" = true;
  };

  env = {
    SDL_VIDEODRIVER = "x11";
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      libGL
      libX11
      libXext
      libXcursor
      libXi
      libXrandr
      libXfixes
      libXrender
      libxcb
      libpulseaudio
      alsa-lib
      libxkbcommon
    ];
  };

  meta = {
    description = "FEZ (native Linux, GOG)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "fez";
  };
}
