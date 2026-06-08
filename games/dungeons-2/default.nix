{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # GOG native-Linux release of Dungeons 2 (Realmforge/Kalypso 2015), base
  # game v2.0.0.1 (gog_dungeons_2_2.0.0.1.sh, 2,663,810,562 bytes). The GOG
  # mojosetup .sh installer is a shell-script header followed by a zip
  # archive, so unzip handles it directly. Layout (confirmed against the AUR
  # dungeons-2-gog PKGBUILD): data/noarch/game/ holds the Unity 5 standalone
  # player Dungeons2.x86_64 plus a bundled mono runtime under mono/. The
  # installer also drops a broken launcher shim named "Dungeons2" (no
  # extension) which we delete. The game ships both x86 and x86_64 Unity
  # builds; we run the 64-bit binary. The three DLCs (a_chance_of_dragons,
  # a_game_of_winter, a_song_of_sand_and_fire) are separate mojosetup .sh
  # overlays onto the same tree and are layered in post-test if wanted.
  #
  # hash is the sha256 of the GOG offline installer gog_dungeons_2_2.0.0.1.sh
  # as distributed in the Dungeons 2 [GOG] [x86, amd64] torrent
  # (e9ab64e2f428201e22b1ee445e559898746b9249335d1c4765b50a40597559aa). GOG
  # reships v2.0.0.1 over time, so this differs from the older copy pinned in
  # the AUR dungeons-2-gog PKGBUILD; the extracted Unity tree is identical.
  installer = fetchIpfs {
    cid = "QmdzEMeM1wbYdLgt6daJWabcjzBoeSLnVPZhwJcjWsqcs3";
    fallbackUrl = "";
    hash = "sha256-6atk4vQoIB4ise5EXlWYmHRrkkkzXRxHZbUKQFl1Wao=";
    name = "gog_dungeons_2_2.0.0.1.sh";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dungeons-2";

  src = installer;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract" || true
    cp -r "$TMPDIR/extract/data/noarch/game/"* "$out"/
    # The GOG installer ships a broken non-executable launcher shim; the
    # actual binary is Dungeons2.x86_64. Drop the shim if present.
    rm -f "$out/Dungeons2"
    chmod +x "$out/Dungeons2.x86_64"
    chmod +x "$out/mono/bin/mono" 2>/dev/null || true
  '';

  runtime = "custom";
  executable = "Dungeons2.x86_64";
  executableArgs = [
    "-logFile"
    "-"
  ];

  # The 64-bit Unity client reaches the menu fine, but selecting a campaign
  # (or skirmish) spawns the standalone match server as a SEPARATE process:
  #   mono/bin/mono server/dedicated.server.exe --singleplayer --client-pid N
  # and the client then connects to it over RakNet. That whole server stack is
  # 32-bit — `mono/bin/mono` is an ELFCLASS32 binary (interpreter
  # /lib/ld-linux.so.2) and `server/libRakNet.so` is a 32-bit shared object.
  # Without a multilib FHS the 32-bit loader/libc are absent, the server exec
  # fails, the client never connects, and the game silently drops back to the
  # menu. Enabling multilib mounts /usr/lib32 + the /lib/ld-linux.so.2 shim and
  # lets the server come up. The 32-bit deps (glibc, libstdc++/libgcc for
  # libRakNet) are all covered by strom-fhs' baseTargetPkgs32.
  bwrap.fhsMultilib = true;

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
      SDL2
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libXxf86vm
      xorg.libXinerama
      xorg.libxcb
      xorg.libXau
      xorg.libXdmcp
      zlib
    ];

  env = {
    SDL_VIDEODRIVER = "x11";
  };

  # Unity 5.3 persistentDataPath on Linux:
  # ~/.config/unity3d/<companyName>/<productName>/. Confirmed from the build's
  # globalgamemanagers: company "Realmforge Studios GmbH", product "Dungeons 2".
  # The custom runtime binds $HOME -> $STROM_GAMEDIR, so this persists to
  # ~/.strom/dungeons-2/ across prefix wipes.
  saveLocations = [ ".config/unity3d/Realmforge Studios GmbH/Dungeons 2" ];

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
    description = "Dungeons 2 (Realmforge/Kalypso 2015, native Linux, GOG v2.0.0.1)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dungeons-2";
  };
}
