{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Period-correct GZDoom g3.6.0 -- the engine Total Chaos 1.0 shipped
  # with. nixpkgs gzdoom (4.x) mis-renders the mod (dark box / static
  # noise on a new game). See gzdoom.nix.
  gzdoom = pkgs.callPackage ./gzdoom.nix { };

  # Total Chaos (Wad Squad / Samuel "Wadaholic" Prunskus, 2018): a
  # standalone survival-horror total conversion. Standalone build
  # 1.00.0 -- DOES NOT require DOOM2.WAD. The 1.42 GiB ModDB zip ships
  # the TC data (gamedata/totalchaos.pk3, the GZDoom-IWAD that carries a
  # GAMEINFO lump + the TITLEMAP title screen), a tiny PWAD (doom.wad)
  # supplying the base PLAYPAL/COLORMAP/menu lumps, and resource pk3s
  # (brightmaps/lights/zd_extra). We drop the bundled Windows gzdoom.exe
  # and drive it with the period-correct GZDoom 3.6.0 engine (gzdoom.nix).
  bundle = fetchIpfs {
    cid = "QmW45VEGeZ4qjDvsUkWwCGBpbu353sfLW5budbhpkgNX1c";
    fallbackUrl = "https://www.moddb.com/downloads/mirror/171903/130/11ea5634e4aed9d8e80a77f9e5cd25bb";
    hash = "sha256-ux8i5bu0ZPPon5FVc/zH0NLfZK7RYCyLTOYVazg6vNo=";
    name = "totalchaos_standalone_1000b.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "total-chaos";

  src = bundle;

  nativeBuildInputs = [ unzip ];

  # Pull just the GZDoom-relevant data out of gamedata/; the bundled
  # Windows engine, .NET launcher and soundfonts are not needed (GZDoom
  # carries its own gzdoom.pk3 + soundfont).
  #
  # gamedata/doom.wad is the minimal *base IWAD* (PLAYPAL/COLORMAP/menu
  # patches + a stub MAP01). totalchaos.pk3 is a PWAD-style mod with no
  # IWADINFO of its own, so it must be loaded ON TOP of doom.wad -- see
  # runScript for the load order that fixes the dark-box bug.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" \
      "gamedata/totalchaos.pk3" \
      "gamedata/doom.wad" \
      "gamedata/brightmaps.pk3" \
      "gamedata/lights.pk3" \
      "gamedata/zd_extra.pk3" \
      -d "$TMPDIR/tc"
    cp "$TMPDIR/tc/gamedata"/* "$out"/
  '';

  runtime = "custom";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      # Intentionally NO --expose-wayland: with it, gzdoom's SDL2 backend
      # picks up gamescope's nested Wayland socket and uses the relative-
      # pointer protocol, which under gamescope-nested delivers sustained
      # Y deltas -- the player view pitches up the moment you touch the
      # mouse. Without it, SDL falls back to XWayland inside gamescope,
      # where the legacy X11 input path works correctly. See doom-ii.
      "--force-grab-cursor" = true;
    };
  };

  # GZDoom defaults its config dir to ~/.config/gzdoom; under our bwrap
  # sandbox that resolves to ~/.strom/total-chaos/.config/gzdoom via the
  # bind setup in mk-game. Saves and config persist there.
  runScript = ''
    mkdir -p "$STROM_GAMEDIR/.config/gzdoom"
    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
    export XDG_DATA_HOME="$STROM_GAMEDIR/.local/share"
    # Belt-and-suspenders: even if a future gamescope flag re-exposes the
    # Wayland socket, force SDL to use the XWayland path for input.
    export SDL_VIDEODRIVER=x11
    # doom.wad is the base IWAD; totalchaos.pk3 is loaded as a PWAD ON TOP
    # of it. This is the fix for the "New Game -> small dark box of static
    # noise" bug: the previous packaging used totalchaos.pk3 as the -iwad
    # and doom.wad as a -file, so doom.wad's placeholder MAP01 (a single
    # empty room) shadowed the real Total Chaos MAPS/map01.wad. With
    # totalchaos.pk3 loaded last, its UDMF map01 + MAPINFO win.
    exec ${gzdoom}/bin/gzdoom \
      -fullscreen \
      -iwad "$GAMEDIR/doom.wad" \
      -file \
        "$GAMEDIR/totalchaos.pk3" \
        "$GAMEDIR/brightmaps.pk3" \
        "$GAMEDIR/lights.pk3" \
        "$GAMEDIR/zd_extra.pk3" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "Total Chaos (Wad Squad 2018) -- standalone survival-horror total conversion via GZDoom";
    platforms = [ "x86_64-linux" ];
    mainProgram = "total-chaos";
  };
}
