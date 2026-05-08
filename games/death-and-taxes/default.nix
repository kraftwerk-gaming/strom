{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # GOG Linux release of Death and Taxes (1.2.59 / build 82787). The
  # mojosetup .sh installer is a shell-script header followed by a zip
  # archive, so unzip handles it directly. Layout:
  # data/noarch/game/DeathAndTaxes.x86_64 (Unity 2019 Linux player) +
  # UnityPlayer.so + DeathAndTaxes_Data/.
  installer = fetchIpfs {
    cid = "PLACEHOLDER_CID";
    fallbackUrl = "https://archive.org/download/death-and-taxes-linux/death_and_taxes_1_2_59_82787.sh";
    hash = "sha256-m30ePSntVTmFxXItxgTwRHFE3lLmVD2/3mvln3cSBp0=";
    name = "death-and-taxes-linux-gog-1.2.59.sh";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "death-and-taxes";

  src = installer;

  nativeBuildInputs = [ unzip ];

  # Drop the GOG _s.debug split-debug payloads (~41MB) and the goggame
  # support tooling we don't need at runtime.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract" || true
    cp -r "$TMPDIR/extract/data/noarch/game/"* "$out"/
    chmod +x "$out/DeathAndTaxes.x86_64"
    rm -f "$out"/*_s.debug
  '';

  runtime = "custom";
  executable = "DeathAndTaxes.x86_64";
  # Unity writes Player.log under $HOME/.config/unity3d/... by default, but
  # bwrap's tmpfs $HOME wipes it on exit. Force logs to stdout so any
  # startup error is visible in the launcher output.
  executableArgs = [
    "-logFile"
    "-"
  ];

  # Unity 2019 Linux player needs the standard X11/GL/audio FHS layer.
  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      udev
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
      zlib
    ];

  env = {
    # Force X11 so the bundled UnityPlayer.so doesn't try to autodetect
    # Wayland and crash; gamescope's Xwayland satisfies this.
    SDL_VIDEODRIVER = "x11";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Death and Taxes (Placeholder Gameworks 2020, native Linux, GOG v1.2.59 build 82787)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "death-and-taxes";
  };
}
