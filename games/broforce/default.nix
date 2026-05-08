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
  # GOG Linux release of Broforce (the "Forever" content patch, build
  # 71321). Mojosetup self-extracting installer: shell-script header +
  # zip archive. Standard Unity 5 layout (Broforce.x86_64 + Broforce_Data/).
  installer = fetchIpfs {
    cid = "QmUQN3MxUKAEYQQmmuJp5C663FfNTiDfiBTVGcqwxJsNhM";
    fallbackUrl = "https://archive.org/download/broforce-linux-gog-phoenix-games-lab/broforce_forver_hf_linux_71321.sh";
    hash = "sha256-C8mbrqrKsrdJka9fP6/KDr8rmd8R9hohTfU33wRLV0Q=";
    name = "broforce-forever-linux-gog-71321.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "broforce-data";
    version = "71321";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    # The Broforce.x86_64 ELF NEEDs only libc/libstdc++/libgcc/etc.; all
    # GL/X11/audio/SDL/vulkan libs are loaded via dlopen by libmono and
    # the Unity engine, so we put them on LD_LIBRARY_PATH at runtime.
    # ScreenSelector.so (the Unity standalone "select your monitor"
    # popup helper) and libMonoPosixHelper.so do have NEEDED entries
    # for gtk2/glib/zlib, so add those for autoPatchelf to find.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      gtk2
      gdk-pixbuf
      glib
      zlib
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/Broforce.x86_64"
      # Drop the 32-bit binary; we ship x86_64 only.
      rm -f "$out/Broforce.x86"
      rm -rf "$out/Broforce_Data/Mono/x86" "$out/Broforce_Data/Plugins/x86"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "broforce";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "Broforce.x86_64";
  # Skip the Unity ScreenSelector configuration popup; gamescope already
  # sets the resolution and fullscreens the nested window.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
    # Unity 5 dlopens GL/X11/audio/vulkan/udev/dbus by bare name; provide
    # the full set on LD_LIBRARY_PATH. libudev.so.0 isn't shipped in
    # current nixpkgs (only .so.1), so the engine falls back to the .so.1
    # symlink that comes with systemd's udev component.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        vulkan-loader
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        wayland
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
    description = "Broforce / Broforce Forever (native Linux, GOG build 71321)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "broforce";
  };
}
