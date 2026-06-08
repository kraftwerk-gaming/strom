{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  pkgsi686Linux,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "earth-2150";

  # GOG offline installer for Earth 2150 - Escape from the Blue Planet (the
  # base game of the Earth 2150 Trilogy reissue, Reality Pump 2000). The
  # archive.org item ships the GOG inno-setup installer as a single .exe (no
  # .bin slices), so innoextract pulls the game tree straight out.
  src = fetchIpfs {
    cid = "QmSYnrqEct1KYknMXmg1GRtm9UX562CksbEtRck9BDEtam";
    fallbackUrl = "https://archive.org/download/earth-2150-trilogy-2.1.0.9-gog/Earth%202150%20Trilogy%202.1.0.9%20%5BGOG%5D/setup_earth2150_2.1.0.9.exe";
    hash = "sha256-xL1ZJKUr/HeTpdFqo9kUuxb5MS2fvd970Bp9AJIf5DU=";
    name = "setup_earth2150_2.1.0.9.exe";
  };

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/inno" "$src"
    chmod -R u+w "$TMPDIR/inno"

    # GOG nests the game under app/; hoist it to the install root so
    # Earth2150.exe sits next to its data dirs.
    if [ -d "$TMPDIR/inno/app" ]; then
      mv "$TMPDIR/inno/app"/* "$out"/
    else
      mv "$TMPDIR/inno"/* "$out"/
    fi
    chmod -R u+w "$out"

    # Drop GOG Galaxy / installer scaffolding; strom does not use the
    # Galaxy launcher path. The engine only needs the tree at the root.
    rm -rf \
      "$out/tmp" \
      "$out/commonappdata" \
      "$out/__redist" \
      "$out/__support"
    rm -f \
      "$out"/goggame-*.* \
      "$out"/goggame*.sdb \
      "$out/webcache.zip"
  '';

  runtime = "proton";

  # Earth2150.exe is the base-game engine entry point.
  executable = "Earth2150.exe";

  # The Reality Pump engine writes its config (resolution/renderer) and
  # savegames next to its binary in the install tree, which lands in the
  # per-game fuse-overlayfs upper (persisted via $STROM_GAMEDIR) rather than
  # under drive_c/users/steamuser/...
  saveLocations = [ ];

  env = {
    # Earth 2150 renders through a DirectDraw/Direct3D6-era path (its setup
    # offers DirectX6 / OpenGL / Glide). The community consensus for running
    # it on Wine is to DISABLE DXVK (DXVK crashes the game) and let wined3d
    # translate the legacy DirectDraw calls. PROTON_USE_WINED3D forces the
    # GL-backed wined3d path; ddraw=b routes DirectDraw through wine's
    # builtin implementation rather than any bundled stub.
    PROTON_USE_WINED3D = "1";
    WINEDLLOVERRIDES = "ddraw=b";
    STAGING_WRITECOPY = "1";
    # 2000-era 32-bit engine; keep it from OOMing under modern address-space
    # layout.
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # Earth2150.exe self-validates its install at startup by reading
  # HKLM\Software\TopWare\Earth 2150\BaseGame\FileSystem (DataPath /
  # OutputDir). A fresh Proton prefix lacks that key (the GOG installer
  # would normally write it), so the engine aborts with the modal
  # "Earth 2150 isn't properly installed. Please reinstall program."
  # before the menu. A WINEDEBUG=+reg trace shows the single lookup is
  # under \Registry\Machine (HKLM), so seed system.reg on every launch,
  # pointed at the overlay-mounted game tree (drive Z: maps to /, so
  # $GAMEDIR becomes Z:\<GAMEDIR> with .reg-doubled backslashes).
  preRun = ''
    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    # system.reg always exists once the prefix is created (it precedes
    # preRun on every launch but the first); bootstrap a header on the
    # very first run so the seed has somewhere to land.
    #
    # The header MUST carry "#arch=win64". preRun runs BEFORE proton
    # initialises the prefix, so on the very first launch this bare file
    # is the system.reg that exists when proton copies its win64
    # default_pfx. Proton/wine will not overwrite an existing system.reg,
    # and a header without an #arch line defaults to win32 — which then
    # conflicts with the win64 user.reg/userdef.reg proton installs, and
    # wine aborts with "is a 32-bit installation, it cannot support
    # 64-bit applications." before the engine ever starts. Tagging the
    # bootstrap win64 keeps the whole prefix 64-bit and consistent.
    if [ ! -f "$SYSREG" ]; then
      mkdir -p "$(dirname "$SYSREG")"
      printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\Machine\n\n#arch=win64\n\n' > "$SYSREG"
    fi
    sh ${./seed-registry.sh} "$SYSREG" "$GAMEDIR"
  '';

  # Native 4:3. Earth 2150 crashes when opening the production/research
  # menus at aspect ratios wider than 16:10 (confirmed by GOG support: the
  # construction screen overflows and faults at 16:9), so the engine runs at
  # 1024x768 and gamescope upscales the nest to 1080p with a pillarboxed 4:3.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Confine the pointer to the nest so the RTS edge-scroll reaches the
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

  # KNOWN LIMITATION: the campaign FMV cutscenes (Video/*.wd1, real MPEG-1)
  # play into a DirectDraw hardware OVERLAY surface, which neither wined3d
  # nor any Proton-viable ddraw wrapper (dgVoodoo2 lacks overlay support
  # entirely) can composite -> the cutscenes render BLACK and are skipped
  # with Escape. The game is otherwise fully playable. A real fix needs a
  # custom wine patch that composites ddraw overlays (tracked separately;
  # it requires the wined3d/builtin-ddraw path kept here, NOT a wrapper).
  meta = {
    description = "Earth 2150: Escape from the Blue Planet (Reality Pump 2000, GOG, via Proton -- campaign FMV cutscenes don't render, see note above)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "earth-2150";
  };
}
