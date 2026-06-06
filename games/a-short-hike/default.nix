{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # GOG Linux release of A Short Hike (1.9 v3 / build 51666),
  # a_short_hike_1_9_v3_51666.sh (236,260,231 bytes). The mojosetup .sh
  # installer is a shell-script header followed by a zip archive, so unzip
  # handles it directly. Expected layout:
  # data/noarch/game/AShortHike.x86_64 (Unity Linux player) + UnityPlayer.so
  # + AShortHike_Data/.
  #
  # Source: archive.org item "a-short-hike-linux-gog" (file
  # gog_a_short_hike_1_9_v3_51666.sh, 236,260,231 bytes,
  # md5 ea21100cfa5c574f83ff57a1a1fc9588) — the legitimate DRM-free GOG
  # native-Linux installer.
  installer = fetchIpfs {
    cid = "QmYRmLbaW6FhEhU51pepXRXc1cZrkGvFe1UoFbTtApgK6d";
    fallbackUrl = "https://archive.org/download/a-short-hike-linux-gog/gog_a_short_hike_1_9_v3_51666.sh";
    hash = "sha256-LyyCpIFja1h6IRrOf1yS9SPNiPKgW6Pb/ayEjT9iImY=";
    name = "a-short-hike-linux-gog-1.9v3-51666.sh";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "a-short-hike";

  src = installer;

  nativeBuildInputs = [ unzip ];

  # Drop the GOG _s.debug split-debug payloads and goggame support tooling
  # we don't need at runtime.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract" || true
    cp -r "$TMPDIR/extract/data/noarch/game/"* "$out"/
    chmod +x "$out/AShortHike.x86_64"
    rm -f "$out"/*_s.debug
  '';

  runtime = "custom";
  executable = "AShortHike.x86_64";
  # Unity writes Player.log under $HOME/.config/unity3d/... by default, but
  # bwrap's tmpfs $HOME wipes it on exit. Force logs to stdout so any
  # startup error is visible in the launcher output.
  executableArgs = [
    "-logFile"
    "-"
  ];

  # Unity Linux player needs the standard X11/GL/audio FHS layer.
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

  # Unity persistentDataPath on Linux: ~/.config/unity3d/<company>/<product>/.
  # The native/custom runtime binds $HOME -> $STROM_GAMEDIR, so this persists
  # to ~/.strom/a-short-hike/ across prefix wipes.
  saveLocations = [ ".config/unity3d/adamgryu/A Short Hike" ];

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
    description = "A Short Hike (adamgryu 2019, native Linux, GOG v1.9 v3 build 51666)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "a-short-hike";
  };
}
