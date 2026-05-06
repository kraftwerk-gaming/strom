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
  # GOG Linux release of Super Hexagon (mojosetup self-extracting installer:
  # shell-script header + zip archive). Ships both x86 and x86_64 ELF
  # binaries plus bundled SDL2/GLEW/openal/vorbis libs in x86_64/.
  installer = fetchIpfs {
    cid = "QmQq1TdmAFnEVQ7pVLCEsH72jygtQPp8s2MYKRJVCbpZrf";
    fallbackUrl = "https://archive.org/download/super-hexagon-gog-linux/gog_super_hexagon_2.1.0.4.sh";
    hash = "sha256-S55gmS/xnEx2KZzTgNgxj4q7PknhZq34csa7PDyzyLA=";
    name = "super-hexagon-gog-2.1.0.4.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "super-hexagon-data";
    version = "2.1.0.4";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    # Runtime deps for the x86_64 binary. SDL2/GLEW/openal/vorbis are
    # bundled in x86_64/ next to the binary; libGL/libGLU come from system.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      libGL
      libGLU
    ];

    buildPhase = ''
      runHook preBuild
      # mojosetup .sh is a zip with a shell-script preamble; unzip warns
      # about extra leading bytes but extracts cleanly.
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      # Drop the 32-bit binary tree; we only ship x86_64.
      rm -rf "$out/x86"
      chmod +x "$out/x86_64/superhexagon.x86_64"
      runHook postInstall
    '';

    # Bundled libs in x86_64/ should be found via rpath at runtime.
    appendRunpaths = [ "$ORIGIN" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "super-hexagon";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "x86_64/superhexagon.x86_64";

  env = {
    # The bundled libopenal.so.1 dlopens libpulse.so.0 / libasound.so.2
    # by bare name, so they have to be reachable via LD_LIBRARY_PATH;
    # autoPatchelf only fixes up NEEDED entries, not dlopens.
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      pkgs.libpulseaudio
      pkgs.alsa-lib
    ];
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Super Hexagon (native Linux, GOG v2.1.0.4)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "super-hexagon";
  };
}
