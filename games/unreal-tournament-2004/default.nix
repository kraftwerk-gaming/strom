{
  self,
  lib,
  pkgs,
  fetchurl,
  p7zip,
  unshield,
  autoPatchelfHook,
  stdenv,
  # Runtime dependencies for the native Linux binary
  sdl3,
  openal,
  libGL,
  vulkan-loader,
  libx11,
  libxext,
  libxrandr,
  libpulseaudio,
  alsa-lib,
  libxcursor,
  libxfixes,
  libxi,
  libxkbcommon,
  libXScrnSaver,
  libXtst,
  pipewire,
  wayland,
  zlib,
  libgcc,
}:

let
  iso = fetchurl {
    url = "https://files.oldunreal.net/UT2004.ISO";
    hash = "sha256-Q+kYKuILy8D29FiP7mwbM2wmHxRlQDEYoZc7CbGiJUE=";
    name = "UT2004.ISO";
  };

  patch = fetchurl {
    url = "https://github.com/OldUnreal/UT2004Patches/releases/download/3374-preview-17/OldUnreal-UT2004Patch3374-Linux-6369f34c.tar.bz2";
    hash = "sha256-/PGV58gVe/R3lzYLheXfMWS4Y4KXp/oIzfIAorGxQzo=";
    name = "ut2004-patch-3374-linux.tar.bz2";
  };

  gameData = stdenv.mkDerivation {
    pname = "ut2004-data";
    version = "3374";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      unshield
      autoPatchelfHook
    ];

    # Libraries the UT2004 binary links against
    buildInputs = [
      sdl3
      openal
      libGL
      vulkan-loader
      libx11
      libxext
      libxrandr
      libxcursor
      libpulseaudio
      alsa-lib
      zlib
      libgcc
    ];

    # Ignore optional deps: Steam integration, and SDL3's optional backends
    autoPatchelfIgnoreMissingDeps = [
      "libsteam_api.so"
      "libGLES_CM.so.1"
      "libsndio.so.7"
      "libfribidi.so.0"
      "libthai.so.0"
      "liburing-ffi.so.2"
    ];

    buildPhase = ''
      runHook preBuild

      STAGING="$TMPDIR/staging"
      CABS="$TMPDIR/cabs"
      DEST="$TMPDIR/game"
      mkdir -p "$STAGING" "$CABS" "$DEST"

      # Step 1: Extract ISO
      7z x ${iso} -o"$STAGING" -y \
        -x'!AutoRunData' \
        -x'!SoNow' \
        -x'!Disk1/layout.bin' \
        -x'!Disk1/Setup.*' \
        -x'!Disk1/setup.*'

      # Step 2: Symlink all CABs into a flat directory for unshield
      for f in "$STAGING"/Disk*/*.cab "$STAGING"/Disk*/*.hdr; do
        [ -e "$f" ] || continue
        ln -sf "$f" "$CABS/$(basename "$f")"
      done

      # Step 3: Extract InstallShield CABs
      unshield -d "$TMPDIR/data" x "$CABS/data1.cab"

      # Step 4: Clean Windows-only files from staging
      cd "$TMPDIR/data"
      rm -f All_UT2004.EXE/*.exe 2>/dev/null || true
      find . -path '*/System/*.bat' -delete 2>/dev/null || true
      find . -path '*/System/*.dll' -delete 2>/dev/null || true
      find . -path '*/System/*.exe' -delete 2>/dev/null || true

      # Step 5: Map InstallShield file groups to game directories
      [ -d "All_Animations" ]     && mv All_Animations     "$DEST/Animations"
      [ -d "All_Benchmark" ]      && mv All_Benchmark      "$DEST/Benchmark"
      [ -d "All_ForceFeedback" ]  && mv All_ForceFeedback  "$DEST/ForceFeedback"
      [ -d "All_Help" ]           && mv All_Help           "$DEST/Help"
      [ -d "All_KarmaData" ]      && mv All_KarmaData      "$DEST/KarmaData"
      [ -d "All_Maps" ]           && mv All_Maps           "$DEST/Maps"
      [ -d "All_Music" ]          && mv All_Music          "$DEST/Music"
      [ -d "All_StaticMeshes" ]   && mv All_StaticMeshes   "$DEST/StaticMeshes"
      [ -d "All_Textures" ]       && mv All_Textures       "$DEST/Textures"
      [ -d "All_Web" ]            && mv All_Web            "$DEST/Web"

      [ -d "All_UT2004.EXE" ] && {
        mkdir -p "$DEST/System"
        cp -r All_UT2004.EXE/* "$DEST/System/"
      }

      [ -d "English_Manual" ] && mv English_Manual "$DEST/Manual"

      # English_Sounds_Speech_System_Help contains subdirs that go to root
      [ -d "English_Sounds_Speech_System_Help" ] && {
        cp -r English_Sounds_Speech_System_Help/* "$DEST/"
      }

      [ -d "US_License.int" ] && {
        mkdir -p "$DEST/System"
        cp -r US_License.int/* "$DEST/System/"
      }

      # Step 6: Apply OldUnreal Linux patch
      tar xf ${patch} --overwrite -C "$DEST"

      # Step 7: Fix case-sensitivity conflicts (OldUnreal ships lowercase,
      # base game has mixed case — remove the wrongly-cased originals)
      for f in Bonuspack.u Gui2K4.u Gameplay.u Ipdrv.u Skaarjpack.u \
               StreamLineFX.u UT2K4Assault.u UT2K4AssaultFull.u \
               XVoting.u xWebAdmin.u; do
        [ -f "$DEST/System/$f" ] && rm -f "$DEST/System/$f"
      done

      # Step 8: Remove bundled libopenal (nix store version used via RPATH);
      # keep libSDL3 and libomp since their bundled versions match what the
      # game binaries expect (specific soname versions)
      rm -f "$DEST/System/libopenal.so"*

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mv "$TMPDIR/game" "$out"
      chmod +x "$out/System/UT2004" 2>/dev/null || true
      chmod +x "$out/System/ucc-bin" 2>/dev/null || true
      runHook postInstall
    '';

    # Don't strip game binaries
    dontStrip = true;
  };

in
self.lib.mkGame { inherit lib pkgs; } {
  name = "unreal-tournament-2004";

  src = gameData;

  copyGlobs = [
    "System/*.ini"
    "System/*.log"
  ];

  runtime = "native";
  executable = "System/UT2004";

  # SDL3 dlopen's X11/Wayland/cursor/input libraries at runtime;
  # on NixOS these aren't in standard paths so we must provide them
  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      libx11
      libxext
      libxcursor
      libxfixes
      libxi
      libxrandr
      libXScrnSaver
      libXtst
      libxkbcommon
      libGL
      vulkan-loader
      libpulseaudio
      alsa-lib
      pipewire
      wayland
    ];
  };

  # run without gamescope
  runScript = ''
    mkdir -p "$GAMEDIR/.ut2004"
    ln -sfn "$GAMEDIR/.ut2004" "$HOME/.ut2004"
    export LD_LIBRARY_PATH="$GAMEDIR/System''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec "$GAMEDIR/System/UT2004" "$@"
  '';

  meta = {
    description = "Unreal Tournament 2004 (OldUnreal native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "unreal-tournament-2004";
  };
}
