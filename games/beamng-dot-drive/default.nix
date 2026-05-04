{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  autoPatchelfHook,
  stdenv,
  alsa-lib,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  glib,
  gtk3,
  libGL,
  libpulseaudio,
  libxcb,
  libxkbcommon,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  vulkan-loader,
}:

let
  archive = fetchIpfs {
    cid = "QmPSLRRfK5wTvQPWKxei2xsRGPerpVnoPToxKq8caHuUJC";
    fallbackUrl = "";
    hash = "sha256-45tcG+zsaR3Ho9uKinFdrSvglWfxwp5yoIx6qFoQQsI=";
    name = "beamng-dot-drive.zip";
  };

  # System libraries needed by BeamNG.drive.x64 and libcef.so at runtime.
  systemLibs = [
    alsa-lib
    pkgs.at-spi2-atk
    pkgs.at-spi2-core
    pkgs.atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    glib
    gtk3
    libGL
    libpulseaudio
    libxcb
    libxkbcommon
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    systemd
    pkgs.util-linux
    vulkan-loader
  ];
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "beamng-dot-drive";

  ipfsSources = [ archive ];
  src = archive;

  nativeBuildInputs = [
    p7zip
    autoPatchelfHook
    stdenv.cc.cc.lib
  ]
  ++ systemLibs;

  buildScript = ''
    mkdir -p "$out"
    7z x -y $src -o"$out"
    shopt -s dotglob
    mv "$out/BeamNG.drive"/* "$out"/
    rmdir "$out/BeamNG.drive"
    rm -f "$out/AnkerGames - Free Pre-installed PC Games.url" \
          "$out/Read Me.txt" \
          "$out/Run me!.bat"

    chmod +x "$out/BinLinux/BeamNG.drive.x64" "$out/BinLinux/console.x64" \
              "$out/BinLinux/crashReporter"

    # Patch ELF interpreter and RPATH for system libs; ignore bundled
    # inter-lib deps (they are resolved at runtime via LD_LIBRARY_PATH).
    autoPatchelfIgnoreMissingDeps=("*")
    autoPatchelf "$out/BinLinux"
  '';

  runtime = "native";
  executable = "BinLinux/BeamNG.drive.x64";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  # $GAMEDIR is set before preRun; BinLinux contains bundled .so files.
  preRun = ''
    export LD_LIBRARY_PATH="$GAMEDIR/BinLinux:${lib.makeLibraryPath systemLibs}:''${LD_LIBRARY_PATH:-}"
  '';

  meta = {
    description = "BeamNG.drive (native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "beamng-dot-drive";
  };
}
