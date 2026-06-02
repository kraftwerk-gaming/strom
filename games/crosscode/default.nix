{
  self,
  lib,
  pkgs,
  fetchIpfs,
  stdenv,
  unzip,
}:

let
  # CrossCode + 3 DLC / Bonus (A New Home, Manlea, Ninja Skin),
  # v1.4.2-3 (GOG build 65220), native Linux NW.js. The GOG offline
  # installers are makeself/mojosetup .sh archives whose payload is an
  # appended zip (game tree at data/noarch/game/); `unzip` extracts it
  # directly without running the interactive mojosetup installer. The
  # IA artifact is a tar bundling the base-game .sh plus the three DLC
  # .sh installers, which overlay onto the same game tree.
  installer = fetchIpfs {
    cid = "QmRoRNXvqHwBVnhgPprtpQgYPMxJWoGTVJVsUfC7Lhwnft";
    fallbackUrl = "https://archive.org/download/crosscode-linux-gog/CrossCode_%2B3_DLC_%28v1.4.2.3%29_%5BLinux%2C_GOG%2C_v65220%5D.tar";
    hash = "sha256-LCfNF6ESAJaE0R/pjYSek0huVzVz7oDBYv8Js12kJqI=";
    name = "crosscode-linux-gog.tar";
  };

  gameData = stdenv.mkDerivation {
    pname = "crosscode-data";
    version = "1.4.2-3";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      pkgs.gnutar
    ];

    # mojosetup .sh archives carry ~1MB of leading shell before the
    # zip; unzip warns about the "extra bytes" and processes anyway,
    # but exits non-zero, so guard the warning.
    buildPhase = ''
      runHook preBuild
      tar xf ${installer}
      unzip -q crosscode_1_4_2_3_65220.sh || true
      for dlc in DLC/*.sh; do
        unzip -q -o "$dlc" || true
      done
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/CrossCode" "$out/chrome_crashpad_handler"
      # GOG install bookkeeping the runtime never reads.
      rm -f "$out"/goggame-*.hashdb "$out"/goggame-*.info "$out"/steam_appid.txt
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "crosscode";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  # The nw.js launcher (renamed `CrossCode`). Its RUNPATH is the
  # relative `$ORIGIN/lib`, but the loader does not honour `$ORIGIN`
  # here (the binary execs from the overlay mount, and the bundled
  # libffmpeg.so / libnw.so are not on any absolute search path), so
  # it dies at startup with
  #   CrossCode: error while loading shared libraries: libffmpeg.so:
  #   cannot open shared object file
  # We instead prepend the overlay's own `lib/` to LD_LIBRARY_PATH in
  # runScript (see below), where $STROM_OVERLAY is known.
  executable = "CrossCode";

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        nss
        nspr
        # Chromium's udev_loader dlopens libudev.so.1 to enumerate
        # input/DRM devices; without it the browser process aborts at
        # startup with `FATAL:udev_loader.cc(37) Check failed: false`.
        systemd
        # NW.js' node library (nw_content_renderer_hooks) links
        # libatomic.so.1; without it the renderer aborts with
        # `Failed to load node library (error: libatomic.so.1: ...)`.
        stdenv.cc.cc.lib
        atk
        at-spi2-core
        at-spi2-atk
        cups
        libdrm
        mesa
        libGL
        libglvnd
        libgbm
        pango
        cairo
        glib
        gtk3
        gdk-pixbuf
        expat
        dbus
        libdbusmenu
        libxkbcommon
        alsa-lib
        libpulseaudio
        libuuid
        xorg.libX11
        xorg.libXcomposite
        xorg.libXdamage
        xorg.libXext
        xorg.libXfixes
        xorg.libXrandr
        xorg.libXcursor
        xorg.libXi
        xorg.libXtst
        xorg.libXScrnSaver
        xorg.libxcb
        xorg.libxshmfence
      ]
    );
  };

  # The bundled NW.js/Chromium stack (libnw.so, libffmpeg.so, ...)
  # lives in the overlay's `lib/`; the binary's `$ORIGIN/lib` RUNPATH
  # isn't honoured, so we prepend `$STROM_OVERLAY/lib` to
  # LD_LIBRARY_PATH here (where $STROM_OVERLAY is bound) rather than in
  # `env` (set -u would trip on the unbound var in the outer wrapper).
  # `--no-sandbox`: Chromium's setuid/namespace sandbox can't nest
  # inside our bwrap user namespace and aborts the zygote/GPU process;
  # disabling it lets the renderer come up.
  runScript = ''
    export LD_LIBRARY_PATH="$STROM_OVERLAY/lib:''${LD_LIBRARY_PATH-}"
    exec "$STROM_OVERLAY/CrossCode" --no-sandbox "$@"
  '';

  # CrossCode (nw.js / Chromium) writes its profile + cc.save under
  # $HOME/.config/CrossCode. runtime = "native" binds $HOME to
  # $STROM_GAMEDIR (~/.strom/crosscode), so this persists across
  # overlay rebuilds without an explicit relocation.
  saveLocations = [ ".config/CrossCode" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "CrossCode + 3 DLC (v1.4.2-3, native Linux NW.js, GOG)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "crosscode";
  };
}
