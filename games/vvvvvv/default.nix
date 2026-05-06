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
  # GOG Linux release of VVVVVV (mojosetup self-extracting installer:
  # shell-script header + zip archive). Native x86_64 ELF binary with a
  # bundled libSDL2 in lib64/.
  installer = fetchIpfs {
    cid = "QmS2djVNYi7Dp1JUnJArXyGCkbbqH43HvPkG2dxBqsRiA6";
    fallbackUrl = "https://archive.org/download/vvvvvv-linux-gog-phoenix-game-lab/vvvvvv_2_4_3_83009.sh";
    hash = "sha256-zNDZ0XwVq2PqQDBrLyv7QJL1z8IPEAAHmuG/5JeTvB8=";
    name = "vvvvvv-gog-2.4.3.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "vvvvvv-data";
    version = "2.4.3";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/VVVVVV"
      runHook postInstall
    '';

    # The bundled libSDL2 in lib64/ should be found via rpath at runtime.
    appendRunpaths = [ "$ORIGIN/lib64" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "vvvvvv";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "VVVVVV";

  env = {
    # Bundled libSDL2 dlopens video/audio backends by bare name. Without
    # libGL, libxkbcommon, libwayland-* etc. on LD_LIBRARY_PATH, SDL fails
    # to create a renderer.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        libxkbcommon
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        wayland
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
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
    description = "VVVVVV (native Linux, GOG v2.4.3)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "vvvvvv";
  };
}
