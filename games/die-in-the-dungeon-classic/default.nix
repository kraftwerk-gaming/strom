{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Die in the Dungeon: CLASSIC (Alarts / ATICO, 2021 Brackeys Game Jam 2021.1
  # prototype), version 1.6.2f. Free "name your own price" itch.io release with
  # a genuine native-Linux Unity build:
  #   "Die in the Dungeon 1.6.2f [LINUX].zip" (42,595,566 bytes).
  # Zip contains a single top-level folder
  #   "Die in the Dungeon 1.6.2f [LINUX]/" with the Unity Linux player
  #   ("Die in the Dungeon 1.6.2f [LINUX].x86_64"), UnityPlayer.so and the
  #   _Data/ tree (app.info company "Die in the Dungeon Team", product
  #   "Die in the Dungeon").
  #
  # Source: alarts.itch.io/die-in-the-dungeon, download upload id 7330266
  # (game id 928508). itch serves it from a short-lived signed CDN URL, so
  # there is no stable direct URL for fallbackUrl; the file is pinned to IPFS.
  src = fetchIpfs {
    cid = "QmQznuRJuvebACp4a9bUoy37YoXTtCsKf3khU8At5qN1tp";
    fallbackUrl = "";
    hash = "sha256-+vUI76lU6rIK0vXmPUkju5as7cU/LP+QbcRjK6pqj4M=";
    name = "die-in-the-dungeon-classic-1.6.2f-linux.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "die-in-the-dungeon-classic";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Flatten the bracketed top-level folder into $out and give the player a
  # space-free name so the wrapper's `executable` path is clean.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Die in the Dungeon 1.6.2f [LINUX]/." "$out"/
    mv "$out/Die in the Dungeon 1.6.2f [LINUX].x86_64" "$out/die-in-the-dungeon.x86_64"
    # Unity derives the data-folder name from the binary basename with the
    # extension stripped, i.e. <basename>_Data, so rename to die-in-the-dungeon_Data.
    mv "$out/Die in the Dungeon 1.6.2f [LINUX]_Data" "$out/die-in-the-dungeon_Data"
    chmod +x "$out/die-in-the-dungeon.x86_64"
  '';

  runtime = "custom";
  executable = "die-in-the-dungeon.x86_64";
  # Unity writes Player.log under $HOME/.config/unity3d/... by default, but
  # bwrap's tmpfs $HOME wipes it on exit. Force logs to stdout so any startup
  # error is visible in the launcher output.
  executableArgs = [
    "-logFile"
    "-"
  ];

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

  # Unity persistentDataPath on Linux:
  # ~/.config/unity3d/<company>/<product>/. The native/custom runtime binds
  # $HOME -> $STROM_GAMEDIR, so this persists to ~/.strom/<game>/ across
  # prefix wipes.
  saveLocations = [ ".config/unity3d/Die in the Dungeon Team/Die in the Dungeon" ];

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
    description = "Die in the Dungeon: CLASSIC (Alarts/ATICO 2021, native Linux, itch.io v1.6.2f)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "die-in-the-dungeon-classic";
  };
}
