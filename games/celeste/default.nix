{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  autoPatchelfHook,
  python3,
  stdenv,
}:

let
  # Native Linux build of Celeste (Maddy Makes Games / Matt Thorson),
  # v1.4.0.0. FNA + MonoKickstart engine, bundled libSDL2 / libFNA3D /
  # libfmod in lib64/. The launcher script `Celeste` execs the right
  # `Celeste.bin.*` for the host arch; we always run the x86_64 binary
  # directly to skip the arch probe.
  installer = fetchIpfs {
    cid = "QmSzeKh5AQRjsuawz4u3iut255MKYzA5a6ecwCbBjYqbbS";
    fallbackUrl = "https://archive.org/download/celeste-v-1.4.0.0-linux.-7z/Celeste_%28v1.4.0.0%29_%5BLinux%5D.7z";
    hash = "sha256-jhInOuOKMqClawooAX5gZY7aeYGmI3Ks8jIA4L2+Sg0=";
    name = "celeste-linux-1.4.0.0.7z";
  };

  gameData = stdenv.mkDerivation {
    pname = "celeste-data";
    version = "1.4.0.0";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      autoPatchelfHook
      python3
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
    ];

    buildPhase = ''
      runHook preBuild
      7z x -y ${installer}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r ./. "$out"/
      chmod +x "$out/Celeste" "$out/Celeste.bin.x86_64" "$out/Celeste.bin.x86" || true

      # The bundled libfmod.so.10 / libfmodstudio.so.10 ship with a
      # PT_GNU_STACK program header whose PF_X bit is set, requesting
      # an executable stack. Modern Linux kernels reject the dlopen
      # with `cannot enable executable stack as shared object requires:
      # Invalid argument`, so Mono fails the FMOD P/Invoke and the
      # game crashes on first audio init with
      # `System.DllNotFoundException: libfmodstudio.so.10`.
      # patchelf 0.15 has no --clear-execstack flag yet, so we strip
      # the X bit by hand: walk the program-header table, find each
      # PT_GNU_STACK entry (p_type = 0x6474E551) and clear PF_X
      # (bit 0) in p_flags.
      python3 ${./clear-execstack.py} \
        "$out/lib64/libfmod.so.10" \
        "$out/lib64/libfmodstudio.so.10" \
        "$out/lib64/libfmod_SDL.so"

      runHook postInstall
    '';

    # MonoKickstart binary loads bundled libSDL2 / libFNA3D / libfmod
    # out of lib64/ relative to the executable. stdenv's default
    # `_moveLib64` would also merge lib/ + lib64/ into a single lib/,
    # which both breaks MonoKickstart and fails on the same-name files
    # present in both trees.
    appendRunpaths = [ "$ORIGIN/lib64" ];
    dontMoveLib64 = true;

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "celeste";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "Celeste.bin.x86_64";

  env = {
    # Bundled libSDL2 (2018-era) dlopens video / audio backends by
    # bare name: libGL, libxkbcommon, libwayland-*, libpulse,
    # libasound, libX11, etc. Without these on LD_LIBRARY_PATH, SDL2
    # silently falls back to dummy drivers or aborts.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        libxkbcommon
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        wayland
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
      ]
    );
  };

  # Mono's P/Invoke dlopen needs `$STROM_OVERLAY/lib64` ahead of
  # the system libs in LD_LIBRARY_PATH so it finds the bundled
  # libfmod.so.10 / libfmodstudio.so.10 — the binary's RUNPATH has
  # `$ORIGIN/lib64` but dlopen searches LD_LIBRARY_PATH first, and
  # without it the FNA layer crashes on first audio init with
  # `System.DllNotFoundException: libfmodstudio.so.10`. We set this
  # inside `runScript` (which gamescope execs as its inner command),
  # not `env` or `preRun`: putting it in `env` would expand
  # `$STROM_OVERLAY` in the outer wrapper before the overlay is
  # mounted (set -u trips on the unbound variable), and putting it
  # in `preRun` would poison gamescope's own LD_LIBRARY_PATH —
  # gamescope picks up the bundled 2018-era libSDL2 from lib64 and
  # dies with `undefined symbol: SDL_GetWindowSizeInPixels`.
  runScript = ''
    export LD_LIBRARY_PATH="$STROM_OVERLAY/lib64:''${LD_LIBRARY_PATH-}"
    # MonoKickstart's signal masking is incomplete: on a normal exit(0)
    # Mono's mono_handle_native_crash fires anyway, dumping a "Native
    # stacktrace" + /proc/self/maps to stderr and then execlp()ing
    # `xdg-open <errorLog>`. On this host xdg-open is a `set -x` shell
    # script that tries `alacritty --execute vim`, which (a) fails with
    # `unexpected argument '--execute'` and (b) keeps the terminal busy
    # with set-x trace lines after the game window closes.
    # `no-gdb-backtrace` skips the in-handler gdb invocation, and
    # closing stdin + redirecting the game's stdout/stderr to a log
    # file keeps any remaining handler output from hijacking the
    # parent terminal. `STROM_GAMEDIR` is the per-game state dir
    # (~/.strom/celeste).
    export MONO_DEBUG="''${MONO_DEBUG:+$MONO_DEBUG,}no-gdb-backtrace"
    mkdir -p "$STROM_GAMEDIR"
    exec "$STROM_OVERLAY/Celeste.bin.x86_64" "$@" \
      </dev/null \
      >>"$STROM_GAMEDIR/celeste.log" \
      2>&1
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Celeste (native Linux, v1.4.0.0)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "celeste";
  };
}
