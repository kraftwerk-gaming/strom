{
  self,
  lib,
  pkgs,
  fetchIpfs,
  libarchive,
  autoPatchelfHook,
  stdenv,
}:

let
  # See inotify-stub.c: makes a failed inotify_add_watch (ENOSPC/EMFILE)
  # non-fatal so PZ's DebugFileWatcher can't NPE-crash MainThread at startup
  # when the host's per-user inotify watch pool is exhausted.
  inotifyStub = pkgs.runCommandCC "pz-inotify-stub" { } ''
    mkdir -p "$out/lib"
    $CC -shared -fPIC -O2 -o "$out/lib/libpz-inotify-stub.so" \
      ${./inotify-stub.c} -ldl
  '';

  # GOG Linux release of Project Zomboid v41.78.16 stable (build 89157).
  # The .sh is a mojosetup self-extracting installer (shell-script header
  # + zip). The game data lives at data/noarch/game/projectzomboid/ with
  # a bundled 64-bit OpenJDK in `jre64/` and native libs in `linux64/`.
  installer = fetchIpfs {
    cid = "QmRcW42meitnUQ7xDXYBT6piM4YwqtJPN4Q9UF3P7PPRnH";
    fallbackUrl = "https://archive.org/download/project-zomboid-linux-gog/project_zomboid_41_78_16_stable_89157.sh";
    hash = "sha256-AtY50ZILJRSXcZa4Gbkhb+yRsOvXehaddUUDeF0w6us=";
    name = "project_zomboid_41_78_16_stable_89157.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "project-zomboid-data";
    version = "41.78.16-89157";

    src = installer;
    dontUnpack = true;

    nativeBuildInputs = [
      libarchive
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      libGL
      alsa-lib
      libpulseaudio
      freetype
      fontconfig
      harfbuzz
      xorg.libSM
      xorg.libICE
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libXi
      xorg.libXtst
      xorg.libXrandr
      xorg.libXcursor
      xorg.libxcb
    ];

    # libfmod{,studio}.so.13 ship as `*.so.13.6` only - no SONAME-style
    # alias - so autoPatchelf can't see them under the requested
    # `libfmod.so.13` name. Mojosetup creates the alias at install time
    # but we bypass mojosetup; recreate the symlinks ourselves so the
    # dlopens from libfmodintegration64.so + libfmodstudio.so.13.6 hit
    # the bundled native via DT_RUNPATH (set via appendRunpaths below).
    appendRunpaths = [ "$ORIGIN/linux64" ];
    autoPatchelfIgnoreMissingDeps = [
      "libfmod.so.13"
      "libfmodstudio.so.13"
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      # Extract the data/noarch/game/ subtree, stripping its 3 prefix
      # components. That leaves: projectzomboid.sh (top-level launcher
      # invoked as the executable), docs/, and projectzomboid/ (game
      # libs + bundled jre64). The launcher cd's into ./projectzomboid
      # before exec'ing ProjectZomboid64, so the relative layout matters.
      bsdtar -xf ${installer} --strip-components=3 'data/noarch/game/'
      cp -r ./* "$out"/
      chmod -R u+w "$out"
      chmod +x "$out/projectzomboid.sh" \
               "$out/projectzomboid/ProjectZomboid64" \
               "$out/projectzomboid/jre64/bin/"*
      # SONAME aliases for the bundled FMOD natives so dlopen by short
      # name (libfmod.so.13 / libfmodstudio.so.13) hits the .so.13.6.
      ln -s libfmod.so.13.6 "$out/projectzomboid/linux64/libfmod.so.13"
      ln -s libfmodstudio.so.13.6 "$out/projectzomboid/linux64/libfmodstudio.so.13"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "project-zomboid";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  # The bundled JRE + LWJGL stack dlopens libGL / libpulse / libfmod /
  # libfreetype by bare name from $LD_LIBRARY_PATH or DT_RUNPATH. The
  # native runtime can't supply /usr/lib for the bare-name dlopens, so
  # use the custom FHS env.
  runtime = "custom";
  executable = "projectzomboid.sh";

  # projectzomboid.sh preserves an inherited $LD_PRELOAD (it prepends to
  # ${LD_PRELOAD}), so exporting the inotify stub here carries through to
  # ProjectZomboid64. See inotifyStub above for the why.
  runScript = ''
    export LD_PRELOAD="${inotifyStub}/lib/libpz-inotify-stub.so''${LD_PRELOAD:+:$LD_PRELOAD}"
    exec "$STROM_OVERLAY/projectzomboid.sh" "$@"
  '';

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      mesa
      vulkan-loader
      alsa-lib
      libpulseaudio
      freetype
      fontconfig
      harfbuzz
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libXi
      xorg.libXtst
      xorg.libXrandr
      xorg.libXcursor
      xorg.libxcb
      zlib
      udev
    ];

  preRun = ''
    # projectzomboid.sh writes its log under $HOME/Zomboid (a directory
    # it creates if missing). $HOME is bound to $STROM_GAMEDIR in our
    # native/custom runtime so saves and logs persist across launches.
    mkdir -p "$HOME/Zomboid"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Project Zomboid (The Indie Stone, native Linux GOG v41.78.16 build 89157)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "project-zomboid";
  };
}
