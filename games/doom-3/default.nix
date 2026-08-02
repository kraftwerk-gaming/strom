{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dhewm3,
  unzip,
}:

let
  # Doom 3 (id Software 2004, id Tech 4). Driven by dhewm3, the
  # maintained GPL source port of the id Tech 4 engine: it runs natively
  # on Linux and needs nothing from the 2004 Windows build but the
  # retail .pk4 assets. Same shape as games/doom and games/doom-ii,
  # which pair id data files with an open-source engine (GZDoom there,
  # dhewm3 here).
  #
  # The base set is the fully patched 1.3.1 asset list dhewm3 expects:
  # pak000.pk4 - pak008.pk4 (pak005+ are the 1.1/1.2/1.3 patch paks).
  # game00.pk4 - game03.pk4 also ship in the archive; those only carry
  # the Windows gamex86.dll game code, which dhewm3 replaces with its
  # own base.so / d3xp.so, so they are dropped.
  basePaks = fetchIpfs {
    cid = "QmNgBDxMtJ4uwjA3jdaEkrQJGP8jeVxrnght5H7THeB42h";
    fallbackUrl = "https://archive.org/download/doom-3-paks/doom3%20paks.zip";
    hash = "sha256-rn2i4O5Zs4iSGHOW0Fd2AQmhjguSHRctrpZYZm4cIXo=";
    name = "doom-3-base-paks.zip";
  };

  # Resurrection of Evil (Nerve Software 2005), the official expansion.
  # Its assets go in d3xp/; dhewm3's main-menu Mods entry switches
  # fs_game to it, and dhewm3 ships the matching d3xp.so game library.
  roePaks = fetchIpfs {
    cid = "QmcgT8A8pcUzGvWzrthMGZv3w9Pq8vUas1sh5NvSNsWXfQ";
    fallbackUrl = "https://archive.org/download/doom-3-roe-paks/doom3%20roe%20paks.zip";
    hash = "sha256-Fq5mpVXr+QESDzBvuWOQvjvGNW9wMvkYcMTnk0962T4=";
    name = "doom-3-roe-paks.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "doom-3";

  src = basePaks;
  ipfsSources = [
    basePaks
    roePaks
  ];

  nativeBuildInputs = [ unzip ];

  # Both zips wrap their paks in one directory ("doom3 paks/",
  # "doom3 roe paks/"), so extract with -j and lay the files out the way
  # the engine wants: base/ for the game, d3xp/ for the expansion.
  buildScript = ''
    mkdir -p "$out/base" "$out/d3xp"
    unzip -j -q "$src" '*/pak0*.pk4' -d "$out/base"
    unzip -j -q ${roePaks} '*/pak0*.pk4' -d "$out/d3xp"
  '';

  runtime = "native";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      # dhewm3 is SDL2; keep it on the XWayland path inside gamescope
      # (see SDL_VIDEODRIVER below) and let gamescope own the pointer
      # grab so mouse look stays in relative mode across the
      # menu/gameplay cursor toggle.
      "--force-grab-cursor" = true;
    };
  };

  runScript = ''
    # dhewm3 splits its writable state across the XDG dirs: dhewm.cfg /
    # doomkey / xpkey under XDG_CONFIG_HOME/dhewm3, savegames and logs
    # under XDG_DATA_HOME/dhewm3. runtime = "native" binds $HOME to
    # $STROM_GAMEDIR (~/.strom/doom-3), so both persist across overlay
    # rebuilds without any relocation.
    export XDG_DATA_HOME="$STROM_GAMEDIR/.local/share"
    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
    # Same reason as games/doom: gamescope's nested Wayland relative-
    # pointer path pitches the view; the XWayland input path is correct.
    export SDL_VIDEODRIVER=x11
    # fs_basepath must be passed explicitly -- dhewm3 looks next to its
    # own binary (the read-only nixpkgs store path) and in the XDG dirs,
    # never in cwd, so it would not find the overlay's base/ otherwise.
    # r_mode -1 + r_customWidth/Height pin the window to gamescope's
    # 1920x1080; r_aspectRatio 1 gives the matching 16:9 gameplay FOV
    # (default 0 is 4:3 and squeezes the view). The main menu still
    # pillarboxes to 4:3 -- that is r_scaleMenusTo43, on by default,
    # and is how the original 2D menu art is meant to be shown.
    # The trailing "$@" is a reproduction seam, not decoration: argv
    # forwards intact from bin/doom-3 -> doom-3-inner ->
    # gamescope-wrapper -> this runscript, so any reviewer can drive the
    # engine directly, e.g.
    #   nix run .#doom-3 -- +set g_skill 1 +map game/mars_city1
    # boots straight into gameplay instead of the menu. Worth keeping on
    # every native-runtime game: it turns "trust the log" into "verify
    # it yourself" without a debug build or a patched wrapper.
    # in_tty 0 disables dhewm3's dedicated-console terminal support, and it
    # is load-bearing here rather than cosmetic. id Tech 4 puts stdin into
    # raw mode with tcsetattr at startup (the binary imports
    # tcgetattr/tcsetattr and carries the in_tty cvar). A background process
    # calling tcsetattr raises SIGTTOU, which the kernel delivers to the
    # WHOLE process group -- and `tostop` does not matter for this path. So
    # launching the game as a background job on a terminal, e.g.
    # `nix run .#doom-3 &`, froze gamescope and the wrapper in state T
    # (wchan=do_signal_stop) while dhewm3 itself ran on, because dhewm3
    # catches SIGTTOU ("Sent to background, disabling terminal support")
    # and the compositor does not. A suspended compositor never maps a
    # window, so the game blocked in poll() and the launch looked like a
    # silent hang: startup log up to "Will use display 0", no window, no
    # error. `kill -CONT` on the process group brought it up instantly.
    # Reproducible headlessly: `set -m; <wrapper> &` leaves gamescope in T.
    # No other engine in the repo does this -- retroarch and dolphin have
    # zero tcsetattr references -- so this belongs here and not in
    # lib/gamescope.nix.
    exec ${dhewm3}/bin/dhewm3 \
      +set in_tty 0 \
      +set fs_basepath "$GAMEDIR" \
      +set r_fullscreen 1 \
      +set r_customWidth 1920 \
      +set r_customHeight 1080 \
      +set r_mode -1 \
      +set r_aspectRatio 1 \
      "$@"
  '';

  # Inert for runtime = "native" (lib/proton.nix is the only consumer),
  # kept as the record of where user state lives -- verified from a
  # headless run: ~/.strom/doom-3/.config/dhewm3/base/dhewm.cfg and
  # ~/.strom/doom-3/.local/share/dhewm3/. $HOME is $STROM_GAMEDIR here,
  # not a tmpfs, so nothing is at risk of a prefix wipe.
  saveLocations = [
    ".config/dhewm3"
    ".local/share/dhewm3"
  ];

  meta = {
    description = "Doom 3 + Resurrection of Evil (id Software 2004, via dhewm3)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "doom-3";
  };
}
