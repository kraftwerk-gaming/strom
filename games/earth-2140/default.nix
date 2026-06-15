{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  pkgsi686Linux,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "earth-2140";

  # GOG offline installer for Earth 2140 (Reality Pump / TopWare 1997). The
  # GOG reissue is an SDL2 source port (SDL2 + SDL2_mixer + smpeg, no
  # DirectDraw), shipped as a single inno-setup .exe; innoextract pulls the
  # game tree straight out.
  src = fetchIpfs {
    cid = "QmZnCAckaMvrujj6B2Ym3arx57HmsX25inPbGzoELuWN6a";
    fallbackUrl = "https://archive.org/download/setup_earth_2140_1.1_75177/setup_earth_2140_1.1_%2875177%29.exe";
    hash = "sha256-cUd0I32pZIRNZOy08bG0kI6xKt1WfX9VlmOwG0P/hmw=";
    name = "setup_earth_2140_1.1.exe";
  };

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/inno" "$src"
    chmod -R u+w "$TMPDIR/inno"

    # This installer lays the game out at the root (Earth2140.exe next to
    # GameData/ and the SDL2 dlls); the app/ subdir only holds GOG icon +
    # webcache scaffolding. Move the whole tree, then drop GOG cruft.
    mv "$TMPDIR/inno"/* "$out"/
    chmod -R u+w "$out"

    # Drop GOG Galaxy / installer scaffolding; strom does not use the
    # Galaxy launcher path.
    rm -rf \
      "$out/tmp" \
      "$out/commonappdata" \
      "$out/__redist" \
      "$out/__support" \
      "$out/app"
    rm -f \
      "$out"/goggame-*.* \
      "$out"/goggame*.sdb \
      "$out/webcache.zip"
  '';

  runtime = "proton";

  # Earth2140.exe is the GOG SDL2 source-port entry point (GOG's
  # playTasks primary task points here).
  executable = "Earth2140.exe";

  # The engine writes config/savegames next to its binary in the install
  # tree, which lands in the per-game fuse-overlayfs upper (persisted via
  # $STROM_GAMEDIR) rather than under drive_c/users/steamuser/...
  saveLocations = [ ];

  env = {
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # Native 4:3 era engine; render at 1024x768 and let gamescope upscale the
  # nest to 1080p with a pillarboxed 4:3.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Confine the pointer to the nest so RTS edge-scroll reaches the
      # viewport edge instead of the cursor escaping the window.
      "--force-grab-cursor" = true;
    };
  };

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
    pkgs.python3
    pkgs.mesa
    pkgs.vulkan-loader
    pkgs.libGL
    pkgs.libx11
    pkgs.libxext
    pkgs.libxcb
    pkgs.libxcursor
    pkgs.libxrandr
    pkgs.libxi
    pkgs.libxfixes
    pkgs.libxrender
    pkgs.libxcomposite
    pkgs.libxinerama
    pkgs.libxxf86vm
    pkgs.libxau
    pkgs.libxdmcp
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgsi686Linux.freetype
    pkgsi686Linux.glibc
    pkgsi686Linux.glib
    pkgsi686Linux.libx11
    pkgsi686Linux.libxext
    pkgsi686Linux.libxcb
    pkgsi686Linux.libxcursor
    pkgsi686Linux.libxrandr
    pkgsi686Linux.libxi
    pkgsi686Linux.libxfixes
    pkgsi686Linux.libxrender
    pkgsi686Linux.libxcomposite
    pkgsi686Linux.libxinerama
    pkgsi686Linux.libxxf86vm
    pkgsi686Linux.libxau
    pkgsi686Linux.libxdmcp
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Earth 2140 (Reality Pump / TopWare 1997, GOG Trilogy) via Proton";
    platforms = [ "x86_64-linux" ];
    mainProgram = "earth-2140";
  };
}
