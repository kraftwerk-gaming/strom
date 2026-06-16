{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  p7zip,
  autoPatchelfHook,
  stdenv,
  # Runtime libraries the native OldUnreal binary + render/audio drivers
  # link against / dlopen (System64/*.so).
  SDL2,
  openal,
  libGL,
  vulkan-loader,
  libxmp,
  mpg123,
  libsndfile,
  libgcc,
  libx11,
  libxext,
  libxrandr,
  libxcursor,
  libxi,
  libxfixes,
  libxkbcommon,
  libpulseaudio,
  alsa-lib,
  wayland,
}:

let
  # Unreal Gold (Epic/Digital Extremes 1998, Gold re-release adds Return to
  # Na Pali), GOG build 2.0.0.6 as a single GOG Inno Setup installer .exe.
  # innoextract --gog yields the full original game tree (System/, Maps/,
  # Textures/, Sounds/, Music/, Meshes/, ...) nested under app/.
  base = fetchIpfs {
    cid = "QmQo8zf4inN41Bh8FJdas3qCCmw42F47u9yqkCze3ZYcTc";
    fallbackUrl = "https://archive.org/download/Unreal-GOG-Collection/Unreal%20Gold/setup_unreal_gold_2.0.0.6.exe";
    hash = "sha256-681+Uae9f5Wxkp888ruu/9u5qKyBGjvKpyRgITiA1GM=";
    name = "setup_unreal_gold_2.0.0.6.exe";
  };

  # OldUnreal v227k native Linux amd64 patch: ships System64/ (the native
  # ELF binary `unreal-bin-amd64`, render/audio driver .so's and bundled
  # libSDL3/libopenal/libxmp/libmpg123/libsndfile) plus refreshed
  # System/*.u packages, SystemLocalized/ and updated Maps/Textures.
  # Overlaid on top of the GOG base tree to turn the Windows-only install
  # into a native Linux one — the same arrangement as the unreal-tournament
  # recipe.
  patch = fetchIpfs {
    cid = "QmPDmGmwRcPyxMAXStAVf2Hg4s1SdA7ZNB6JvtnvhE5phx";
    fallbackUrl = "https://github.com/OldUnreal/Unreal-testing/releases/download/v227k_14/OldUnreal-UnrealPatch227k-Linux.tar.bz2";
    hash = "sha256-lVADQ8C8RXqncGO8bvuvgweXm9ALbqPUCGzifF0HD40=";
    name = "oldunreal-unrealpatch227k-linux.tar.bz2";
  };

  gameData = stdenv.mkDerivation {
    pname = "unreal-data";
    version = "227k";

    dontUnpack = true;

    nativeBuildInputs = [
      innoextract
      p7zip
      autoPatchelfHook
    ];

    buildInputs = [
      SDL2
      openal
      libGL
      vulkan-loader
      libxmp
      mpg123
      libsndfile
      libgcc
    ];

    # Steam integration + SDL2 optional backends the drivers reference
    # but don't require; libSDL3 is bundled in System64/.
    autoPatchelfIgnoreMissingDeps = [
      "libsteam_api.so"
      "libGLES_CM.so.1"
      "libSDL3.so.0"
      "libSDL3_ttf.so.0"
    ];

    buildPhase = ''
      runHook preBuild

      DEST="$TMPDIR/game"
      mkdir -p "$DEST"

      # Base GOG tree (game data is nested under app/).
      innoextract --gog -d "$TMPDIR/iss" ${base}
      cp -r "$TMPDIR/iss/app"/. "$DEST"/
      # GOG installer debris.
      rm -rf "$DEST/__redist" "$DEST/tmp" "$DEST/commonappdata" \
             "$DEST/Manual"
      rm -f "$DEST/goggame-"* "$DEST/galaxy_"* \
            "$DEST"/*.ico "$DEST"/GameuxInstallHelper.dll 2>/dev/null || true

      # Overlay the native Linux 227k patch (adds System64/, refreshes
      # System/*.u, SystemLocalized/, updated Maps/Textures).
      tar xjf ${patch} --overwrite -C "$DEST"

      # New Game fix at the data layer. The "Start" button issues a relative
      # client travel (?Difficulty=N?Game=?ClassicMode=...) with no map, so
      # the engine resolves it against [URL] Map=. The stock default
      # Index.unr is a server-lobby map that ships with no retail/GOG build,
      # so New Game dies with "Can't find file 'Index.unr'". The
      # single-player campaign starts on the Vortex Rikers prison ship
      # (Vortex2.unr, present in Maps/). The native binary re-derives [URL]
      # from these Default*.ini templates on startup (a launch-time ini edit
      # gets overwritten), so fix the templates themselves. Startup uses
      # LocalMap (Unreal.unr), so this only affects the new-game target.
      for ini in System/Default.ini System/DefaultLinux.ini \
                 System64/DefaultLinux.ini System/Unreal.ini; do
        if [ -f "$DEST/$ini" ]; then
          sed -i '/^\[URL\]/,/^\[/ s/^Map=.*/Map=Vortex2.unr/' "$DEST/$ini"
        fi
      done

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mv "$TMPDIR/game" "$out"
      chmod +x "$out/System64/unreal-bin-amd64" 2>/dev/null || true
      chmod +x "$out/System64/ucc-bin-amd64" 2>/dev/null || true
      runHook postInstall
    '';

    dontStrip = true;
  };

in
self.lib.mkGame { inherit lib pkgs; } {
  name = "unreal";

  src = gameData;

  ipfsSources = [
    base
    patch
  ];

  runtime = "native";
  executable = "System64/unreal-bin-amd64";

  # The native binary + drivers resolve their sibling engine modules
  # (Core.so, Engine.so, SDLDrv.so ...) by bare soname from the working
  # dir / LD_LIBRARY_PATH; bundled libSDL3 dlopens X11/Wayland/cursor/
  # input + GL + Vulkan + PulseAudio at runtime, so provide those from
  # the store.
  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      SDL2
      openal
      libGL
      vulkan-loader
      libxmp
      mpg123
      libsndfile
      libx11
      libxext
      libxrandr
      libxcursor
      libxi
      libxfixes
      libxkbcommon
      libpulseaudio
      alsa-lib
      wayland
    ];
  };

  # OldUnreal 227 on Linux writes its config + savegames next to the
  # binary in System64/ (and ../Save). The native runtime runs from the
  # writable fuse-overlayfs upper ($STROM_GAMEDIR), so that persists in
  # ~/.strom/unreal/ across prefix/overlay wipes.
  saveLocations = [ ];

  runScript = ''
    cd "$GAMEDIR/System64"

    # The native OldUnreal binary derives its active config filename from
    # its own basename: unreal-bin-amd64 reads/writes UnrealLinux.ini, NOT
    # Unreal.ini. It auto-creates UnrealLinux.ini from DefaultLinux.ini on
    # first launch, so seed it ourselves up-front and patch it before the
    # engine reads it.
    INI=UnrealLinux.ini
    if [ ! -f "$INI" ] && [ -f DefaultLinux.ini ]; then
      cp DefaultLinux.ini "$INI"
    fi
    if [ ! -f User.ini ] && [ -f DefUser.ini ]; then
      cp DefUser.ini User.ini
    fi

    if [ -f "$INI" ]; then
      chmod u+w "$INI"

      # Belt-and-suspenders enforcement of the data-layer ini fixes on an
      # already-persisted UnrealLinux.ini from an earlier launch. sed -i
      # renames a temp into place, which fails with EXDEV on the game's
      # fuse-overlayfs upper, so edit via a $TMPDIR scratch file and write
      # back with a truncating redirect (no cross-device rename).
      _patch_ini() {
        local tmp
        tmp="$(mktemp)"
        # New Game fix: the menu's "Start" issues a relative client travel
        # (?Difficulty=N?Game=?ClassicMode=...) with no map, so the engine
        # resolves it against [URL] Map=. The stock value Index.unr is a
        # server-lobby map absent from every retail/GOG build, so New Game
        # dies with "Can't find file 'Index.unr'". The campaign starts on
        # the Vortex Rikers prison ship (Vortex2.unr); point the default map
        # there. Startup uses LocalMap (Unreal.unr), so only New Game moves.
        # Also force windowed mode — an SDL fullscreen request inside
        # gamescope's nested Xwayland trips the engine; run windowed at the
        # full nest size and let gamescope present it fullscreen 1:1.
        sed -e '/^\[URL\]/,/^\[/ s/^Map=.*/Map=Vortex2.unr/' \
            -e '/^\[SDL.*Client\]/,/^\[/ {
              s/^StartupFullscreen=.*/StartupFullscreen=False/
              s/^WindowedViewportX=.*/WindowedViewportX=1920/
              s/^WindowedViewportY=.*/WindowedViewportY=1080/
              s/^FullscreenViewportX=.*/FullscreenViewportX=1920/
              s/^FullscreenViewportY=.*/FullscreenViewportY=1080/
            }' \
            -e '/^\[Engine\.Engine\]/,/^\[/ s/^StartupFullscreen=.*/StartupFullscreen=False/' \
            "$INI" > "$tmp"
        cat "$tmp" > "$INI"
        rm -f "$tmp"
      }
      _patch_ini
    fi

    export LD_LIBRARY_PATH="$GAMEDIR/System64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ./unreal-bin-amd64 "$@"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Unreal (Gold; Epic/Digital Extremes 1998, OldUnreal v227k native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "unreal";
  };
}
