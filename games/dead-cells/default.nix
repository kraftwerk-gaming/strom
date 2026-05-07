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
  # GOG Linux release of Dead Cells (1.26.0 / build 75679). The archive
  # is a tar containing the main mojosetup installer .sh plus a DLC/
  # subdirectory with five expansion installers. We extract only the
  # base game; mojosetup .sh files are shell-script header + zip
  # archive, so unzip handles them directly.
  installer = fetchIpfs {
    cid = "QmX4JAig3PaNMwjLxJ85FwB6vR6TP6fbCywAQGbeYee6M9";
    fallbackUrl = "https://archive.org/download/dead-cells-linux-gog-phoenix-games-lab/Dead_Cells_%2B5_DLC_%28v1.26.0%29_%5BLinux%2C_GOG%2C_v75679%5D.tar";
    hash = "sha256-imNXjjQ0e/6JNCrMSh0Ba4Ku1IbeRsIdZiCEQ8t/Nqg=";
    name = "dead-cells-linux-gog-1.26.0.tar";
  };

  gameData = stdenv.mkDerivation {
    pname = "dead-cells-data";
    version = "1.26.0";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      wayland
      libxkbcommon
      alsa-lib
      libbsd
      libpng
      zlib
      libvorbis
      libpulseaudio
      xorg.libX11
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXxf86vm
      xorg.libXext
    ];

    buildPhase = ''
      runHook preBuild
      tar -xf ${installer} dead_cells_1_26_0_75679.sh
      unzip -q dead_cells_1_26_0_75679.sh || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/deadcells"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dead-cells";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # The bundled libSDL2-2.0.so.0 dates from 2018 (still lists "Mir" as
  # a video driver) and dlopens libudev/libGL/libwayland/etc. by bare
  # name, so we need an FHS env (which the "native" runtime doesn't
  # provide). Use "custom" so we get buildFHSEnv with targetPkgs.
  runtime = "custom";
  executable = "deadcells";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      udev
      libxkbcommon
      libpulseaudio
      alsa-lib
      dbus
      mesa
      vulkan-loader
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXxf86vm
      xorg.libXinerama
      xorg.libxcb
      wayland
    ];

  env = {
    # The bundled SDL2 segfaults in its Wayland GL context creation
    # against modern Mesa. Force X11 so SDL goes through gamescope's
    # Xwayland instead.
    SDL_VIDEODRIVER = "x11";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Dead Cells (native Linux, GOG v1.26.0 build 75679)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dead-cells";
  };
}
