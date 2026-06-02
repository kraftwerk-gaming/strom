{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  stdenv,
}:

let
  # 4A Games' 2014 native-Linux release of Metro 2033 Redux. The .tar.xz
  # is the official Steam/GOG Linux tree: a single `metro` ELF under
  # `game/`, content.vfx + content??.vfs[0,1] virtual filesystems for
  # assets, libsteam_api.so for Steamworks stubs, and a start.bash
  # launcher. We ship only the `game/` subtree; the top-level
  # `start.bash` / `desktop.bash` are replaced by mk-game's wrapper.
  archive = fetchIpfs {
    cid = "QmRgowFfaJXv3Cvhpe1arUxGPzgAhhcDnG1im6h6oD4NoW";
    fallbackUrl = "";
    hash = "sha256-4gTO00tME8R53zQy7Nx4mgGZhulWkDnDkZSmm13k8KU=";
    name = "metro-2033-redux-linux.tar.xz";
  };

  gameData = stdenv.mkDerivation {
    pname = "metro-2033-redux-data";
    version = "1.0";

    src = archive;

    sourceRoot = ".";

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      libGLU
      openal
      libpulseaudio
      alsa-lib
      libxkbcommon
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXi
      xorg.libXcursor
      xorg.libXinerama
      xorg.libxcb
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r game/* "$out"/
      chmod +x "$out/metro"
      runHook postInstall
    '';

    appendRunpaths = [ "$ORIGIN" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "metro-2033-redux";

  ipfsSources = [ archive ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "custom";
  executable = "metro";

  targetPkgs =
    p: with p; [
      libGL
      libGLU
      libglvnd
      mesa
      vulkan-loader
      openal
      libpulseaudio
      alsa-lib
      libxkbcommon
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXi
      xorg.libXcursor
      xorg.libXinerama
      xorg.libxcb
    ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Metro 2033 Redux (4A Games 2014 native Linux remaster)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "metro-2033-redux";
  };
}
