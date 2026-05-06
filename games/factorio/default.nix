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
  # GOG Linux release of Factorio (mojosetup self-extracting installer:
  # shell-script header + zip archive). Statically-ish linked binary that
  # dlopens GL/X/wayland/audio/vulkan libs at runtime.
  installer = fetchIpfs {
    cid = "QmQ44ijCnBwXp3n9fZHGjmkvKRj2cS9Tx1ef4FXke2r2qg";
    fallbackUrl = "https://archive.org/download/factorio-linux-gog-phoenix-games-lab/Factorio_%5BLinux%2C_GOG%5D/factorio_2_0_73_88209.sh";
    hash = "sha256-mxM8sR9SaLk5RXPBi8xv5MrlHnHDCp4oWgaEP6ke80Y=";
    name = "factorio-gog-2.0.73.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "factorio-data";
    version = "2.0.73";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    # Only the NEEDED libs are autopatched into rpath; the GL/X/audio/etc.
    # libs are loaded via dlopen at runtime and live on LD_LIBRARY_PATH.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
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
      chmod +x "$out/bin/x64/factorio"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "factorio";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "bin/x64/factorio";

  env = {
    # Factorio dlopens GL, X11, wayland, vulkan, audio, dbus, xkbcommon,
    # libdecor at runtime by bare name. Provide them all on LD_LIBRARY_PATH.
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
        vulkan-loader
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
    description = "Factorio (native Linux, GOG v2.0.73)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "factorio";
  };
}
