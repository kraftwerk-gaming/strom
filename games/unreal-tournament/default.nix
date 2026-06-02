{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  autoPatchelfHook,
  stdenv,
  # Runtime libraries the native OldUnreal binary + render/audio drivers
  # link against (System64/*.so).
  SDL2,
  SDL2_ttf,
  openal,
  libGL,
  vulkan-loader,
  libxmp,
  mpg123,
  libsndfile,
  zlib,
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
  # GOTY full version, already merged into a flat game tree (System/,
  # Maps/, Textures/, Sounds/, Music/, ...) and patched to OldUnreal
  # 469D — DRM-free, OldUnreal/Epic-sanctioned archive.org mirror.
  base = fetchIpfs {
    cid = "QmRgRLP6Z1DXxwJ2aVbgmnwMqK1o9T1HkeZfkXFnH3jyDa";
    fallbackUrl = "https://archive.org/download/unreal-tournament-goty-469-c-full-version.-7z/Unreal%20Tournament%20GOTY%20469D%20FullVersion.7z";
    hash = "sha256-DCigDpZP1vPUw0iHRtnZaXnzbZ/alq9PjeEsC+9OO5Y=";
    name = "unreal-tournament-goty-469d.7z";
  };

  # OldUnreal v469e native Linux amd64 patch: ships System64/ (the native
  # ELF binary `ut-bin-amd64`, render/audio driver .so's and bundled
  # libfmod/libxmp/libmpg123/libsndfile) plus refreshed System/*.u
  # packages, SystemLocalized/ and Web/. Overlaid on top of the base
  # tree to upgrade the Windows-only 469D install to a native Linux one.
  patch = fetchIpfs {
    cid = "QmR3az4L1Jpj4Sx6GdgmGkHc2J627RAukeZW4zh2Ziwe4T";
    fallbackUrl = "https://github.com/OldUnreal/UnrealTournamentPatches/releases/download/v469e/OldUnreal-UTPatch469e-Linux-amd64.tar.bz2";
    hash = "sha256-CMgGqjchsZcARaoVitkAUTKdmC6KmjZhFTkA6cy/aww=";
    name = "oldunreal-utpatch469e-linux-amd64.tar.bz2";
  };

  gameData = stdenv.mkDerivation {
    pname = "unreal-tournament-data";
    version = "469e";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      autoPatchelfHook
    ];

    buildInputs = [
      SDL2
      SDL2_ttf
      openal
      libGL
      vulkan-loader
      libxmp
      mpg123
      libsndfile
      zlib
      libgcc
    ];

    # Steam integration + SDL2 optional backends the drivers reference
    # but don't require.
    autoPatchelfIgnoreMissingDeps = [
      "libsteam_api.so"
      "libGLES_CM.so.1"
    ];

    buildPhase = ''
      runHook preBuild

      DEST="$TMPDIR/game"
      mkdir -p "$DEST"

      # Base GOTY tree (System/, Maps/, Textures/, Sounds/, Music/, ...).
      7z x ${base} -o"$DEST" -y >/dev/null

      # Some archive.org repacks nest the tree one level down; flatten if so.
      if [ ! -d "$DEST/System" ] && [ "$(ls -1 "$DEST" | wc -l)" = "1" ]; then
        inner="$DEST/$(ls -1 "$DEST")"
        if [ -d "$inner/System" ]; then
          mv "$inner"/* "$DEST/"
          rmdir "$inner" 2>/dev/null || true
        fi
      fi

      # Overlay the native Linux 469e patch (adds System64/, refreshes
      # System/*.u, SystemLocalized/, Web/, Help/, Textures/).
      tar xjf ${patch} --overwrite -C "$DEST"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mv "$TMPDIR/game" "$out"
      chmod +x "$out/System64/ut-bin-amd64" 2>/dev/null || true
      chmod +x "$out/System64/ucc-bin-amd64" 2>/dev/null || true
      runHook postInstall
    '';

    dontStrip = true;
  };

in
self.lib.mkGame { inherit lib pkgs; } {
  name = "unreal-tournament";

  src = gameData;

  ipfsSources = [
    base
    patch
  ];

  runtime = "native";
  executable = "System64/ut-bin-amd64";

  # The native binary + drivers resolve their sibling engine modules
  # (Core.so, Engine.so, SDLDrv.so ...) by bare soname from the working
  # dir / LD_LIBRARY_PATH, and dlopen X11/Wayland/cursor/input + GL +
  # Vulkan + PulseAudio at runtime; provide those from the store.
  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      SDL2
      SDL2_ttf
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

  # OldUnreal 469 on Linux stores per-user config + savegames under
  # ~/.utpg/. runtime = "native" binds $HOME -> $STROM_GAMEDIR, so that
  # lands in ~/.strom/unreal-tournament/.utpg/ and persists across
  # prefix/overlay wipes.
  runScript = ''
    CONFIGDIR="$HOME/.utpg/System"
    mkdir -p "$CONFIGDIR"

    # OldUnreal defaults to StartupFullscreen=True, but an SDL fullscreen
    # window request inside gamescope's nested Xwayland trips the engine's
    # "Inconsistent SDL window flags" appError (the SDL_WINDOW_FULLSCREEN
    # flag SDL reports back doesn't match what UT asked for) and it aborts
    # before the menu. Run windowed instead and let gamescope present the
    # nested surface fullscreen.
    #
    # On first launch UT generates UnrealTournament.ini/User.ini from the
    # bundled Default.ini/DefUser.ini *after* this script, so seed them
    # here from those templates if absent; then force windowed in the
    # active [SDLDrv.SDLClient] section.
    if [ ! -f "$CONFIGDIR/UnrealTournament.ini" ] \
      && [ -f "$GAMEDIR/System64/Default.ini" ]; then
      cp "$GAMEDIR/System64/Default.ini" "$CONFIGDIR/UnrealTournament.ini"
    fi
    if [ ! -f "$CONFIGDIR/User.ini" ] \
      && [ -f "$GAMEDIR/System64/DefUser.ini" ]; then
      cp "$GAMEDIR/System64/DefUser.ini" "$CONFIGDIR/User.ini"
    fi
    if [ -f "$CONFIGDIR/UnrealTournament.ini" ]; then
      chmod u+w "$CONFIGDIR/UnrealTournament.ini"
      # Force windowed (StartupFullscreen=False) so gamescope presents the
      # nested surface, and size that windowed viewport to the full
      # 1920x1080 nest so the surface fills the output 1:1 — the default
      # 1024x768 leaves the menu letterboxed and centred, so clicks land
      # offset from where they're drawn. Only the [SDLDrv.SDLClient] section
      # is rewritten (sed range from its header to the next [section]).
      sed -i '/^\[SDLDrv\.SDLClient\]/,/^\[/ {
        s/^StartupFullscreen=.*/StartupFullscreen=False/
        s/^WindowedViewportX=.*/WindowedViewportX=1920/
        s/^WindowedViewportY=.*/WindowedViewportY=1080/
        s/^FullscreenViewportX=.*/FullscreenViewportX=1920/
        s/^FullscreenViewportY=.*/FullscreenViewportY=1080/
      }' "$CONFIGDIR/UnrealTournament.ini"
    fi

    export LD_LIBRARY_PATH="$GAMEDIR/System64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    cd "$GAMEDIR/System64"
    exec ./ut-bin-amd64 "$@"
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
    description = "Unreal Tournament (GOTY, 1999; OldUnreal v469e native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "unreal-tournament";
  };
}
