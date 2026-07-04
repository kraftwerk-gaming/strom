{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  src = fetchIpfs {
    cid = "QmXqGFXAh7Y9vzBRXj5cGyjnLFPPsYnMJPZVAoMAbdWmtj";
    hash = "sha256-hi9tn6HC6pgLIAkAoZtnhus7BcYq8B241xBVWqvupoM=";
    name = "balatro-ankergames.rar";
  };

  # For Android: produce a clean Game.love (a zip of the game's lua +
  # assets, with main.lua at the root) to feed the balatromobile APK
  # build (./apk.nix).
  #
  # Balatro ships as a "fused" LÖVE binary: Balatro.exe is love.exe (a
  # Windows PE executable) with the game's .love payload (a zip)
  # appended after it. We must NOT ship the .exe/DLLs to Android —
  # liblove there wants a plain .love. unzip locates a zip's central
  # directory from the END of the file, so it reads the appended
  # payload straight out of Balatro.exe and ignores the PE prefix (it
  # prints a warning about the leading bytes and exits 1 — harmless, so
  # we tolerate it and then assert main.lua is present).
  loveSrc =
    pkgs.runCommandLocal "balatro-love"
      {
        nativeBuildInputs = [
          pkgs.unar
          pkgs.unzip
          pkgs.zip
        ];
      }
      ''
        mkdir -p "$out"
        work=$(mktemp -d)

        # Unpack the RAR distribution to locate the fused LÖVE binary.
        unar -o "$work" ${src}
        exe=$(find "$work" -iname "Balatro.exe" | head -1)
        if [ -z "$exe" ]; then
          echo "ERROR: Balatro.exe not found in archive" >&2
          find "$work" >&2
          exit 1
        fi

        # Extract the appended .love payload from the fused exe.
        game=$(mktemp -d)
        unzip -q -o "$exe" -d "$game" || true
        if [ ! -f "$game/main.lua" ]; then
          echo "ERROR: main.lua not found in .love payload of Balatro.exe" >&2
          ls -la "$game" >&2
          exit 1
        fi

        # Repackage as a clean Game.love with main.lua at the archive root.
        ( cd "$game" && zip -q -r -X "$out/Game.love" . )
      '';

  # Android APK is balatro-specific (it uses balatromobile, which bundles
  # its own LÖVE runtime), so the build lives here rather than in the
  # generic lib/android. It is plugged into the android submodule via
  # `android.outputs.apk` below. balatromobile needs only Python + a JDK,
  # so the free `pkgs` set is enough (no unfree Android SDK).
  balatromobile = pkgs.callPackage ./balatromobile { };
  mobileApk = pkgs.callPackage ./apk.nix {
    inherit balatromobile;
    gameData = loveSrc;
    versionName = "1.0.1o";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "balatro";

  ipfsSources = [ src ];

  src =
    pkgs.runCommandLocal "balatro-data"
      {
        nativeBuildInputs = [ pkgs.unar ];
      }
      ''
        mkdir -p "$out"
        unar -o "$out" ${src}
        extracted=$(echo "$out/"*/)
        mv "$extracted/Balatro/"* "$out/"
      '';

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "proton";
  executable = "Balatro.exe";

  saveLocations = [ "AppData/Roaming/Balatro" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      # Balatro's startup churns its toplevel (the Proton start.exe ->
      # game.exe handoff destroys+recreates the window) fast enough to
      # trip gamescope#1456: the wayland-backend CWaylandInputThread
      # abort()s (confirmed via coredump: SIGABRT in
      # CWaylandInputThread::ThreadFunc), killing the compositor on ~50%
      # of launches ("Parent of gamescopereaper was killed"). PerWindow
      # holds back the outer toplevel mapping until the inner client maps
      # its own, removing the rapid map/unmap that aborts the input
      # thread. Set per-game (not globally) because PerWindow delays
      # window-mapping for slow-intro games (lib/gamescope.nix); Balatro
      # has no intro so the trade-off is free here.
      # (--immediate-flips + --expose-wayland were also dropped: the
      # former is a DRM/embedded-only no-op when nested, the latter forces
      # a wayland session type that misroutes a Proton/Xwayland game.)
      "--virtual-connector-strategy" = "PerWindow";
    };
  };

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # Android build: fill the android submodule's outputs.apk seam (it
  # has no default builder) with the balatromobile-built APK.
  # Consumers: `nix build .#apks.balatro`.
  android.outputs.apk = mobileApk;

  meta = {
    description = "Balatro (via Proton)";
    platforms = [
      "x86_64-linux"
      "aarch64-android"
    ];
    mainProgram = "balatro";
  };
}
