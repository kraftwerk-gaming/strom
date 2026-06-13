{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # SpellForce 2 - Anniversary Edition (THQ Nordic / Grimlore 2017 re-release
  # of the 2006 Shadow Wars RTS/RPG hybrid, bundling Dragon Storm + Faith in
  # Destiny + Demons of the Past, GOG offline installer v2.01.85906). The
  # archive.org mirror repacks the three-part GOG Inno Setup installer
  # (setup_*.exe + .bin disks) into a single ~9.7 GB RAR. innoextract --gog
  # produces the install tree with SpellForce2.exe at the top level. The
  # game is DRM-free and runs under Proton.
  # Pinned to IPFS; the archive.org RAR (9,702,936,912 bytes) remains the
  # public fallback.
  src = fetchIpfs {
    cid = "QmcDUyycudv2RtWB5Yfw2RpDCcdo81B3CdfAmWMcHz4AiC";
    fallbackUrl = "https://archive.org/download/spellforce-2-anniversary-edition/Spellforce%202%20-%20Anniversary%20Edition.rar";
    hash = "sha256-QJMNl94Qz5p/qZVnFgIT44pnVOXVykV9krJHenideDU=";
    name = "spellforce-2-anniversary-edition.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "spellforce-2-anniversary-edition";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" "$src"

    # The RAR's top-level dir name is uploader-chosen; locate the GOG Inno
    # setup exe by glob rather than hardcoding the unverified filename.
    # innoextract --gog reads the .exe header + paired .bin disk chunks.
    setup_exe=$(find "$TMPDIR/rar" -iname 'setup_*spellforce*2*.exe' | sort | head -n1)
    if [ -z "$setup_exe" ]; then
      setup_exe=$(find "$TMPDIR/rar" -iname 'setup_*.exe' | sort | head -n1)
    fi
    if [ -z "$setup_exe" ]; then
      echo "ERROR: no GOG setup_*.exe found inside the RAR" >&2
      find "$TMPDIR/rar" -maxdepth 2 >&2
      exit 1
    fi
    innoextract --gog -d "$TMPDIR/iss" "$setup_exe"

    # GOG Inno layout: game files live at the root of the extract dir; the
    # optional app/ subdir is GOG's pre-1.2 installer convention. Cover both.
    if [ -d "$TMPDIR/iss/app" ]; then
      cp -r "$TMPDIR/iss/app"/. "$out"/
    else
      cp -r "$TMPDIR/iss"/. "$out"/
    fi
    chmod -R u+w "$out"

    # Strip GOG installer scaffolding + Galaxy redists; the engine has no
    # runtime dependency on any of this.
    rm -rf "$out/app" "$out/__redist" "$out/tmp" "$out/commonappdata" \
           "$out/__support"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/goggame-"*.dll \
          "$out/galaxy_"*.exe \
          "$out/autorun.exe" "$out/autorun.inf" \
          "$out/EULA.txt" "$out/webcache.zip"
  '';

  runtime = "proton";
  executable = "SpellForce2.exe";

  # SpellForce 2 writes savegames + config under Documents/SpellForce2
  # (confirmed on the GOG forums and Steam community; the Anniversary
  # Edition kept the original Shadow Wars path). Relocate it into
  # $STROM_GAMEDIR so wineprefix wipes don't take user progress.
  saveLocations = [ "Documents/SpellForce2" ];

  # Seed the load-friendly graphics config on a fresh prefix. The
  # level-load-forever hang on modern hardware has two halves: the
  # WINE_CPU_TOPOLOGY=1:0 affinity cap (env, above) AND a downgraded
  # config.xml -- with the engine's defaults (antialiasing 5,
  # optiontexturesizebias 1, water/blur/glow/sharpen/noise on,
  # 16x terrain anisotropy, shadow maps) the texture-streaming path
  # during a level load deadlocks even with the CPU pinned. The two
  # dominant levers are antialiasing=0 and optiontexturesizebias=8.
  #
  # SpellForce2 writes config.xml to Documents/SpellForce2, which
  # saveLocations relocates to $STROM_GAMEDIR/SpellForce2. The
  # save-relocation symlink is wired up host-side (proton preHook)
  # before this runs, so $STROM_GAMEDIR/SpellForce2 is the live path.
  # Install only if absent so existing players keep their own config.
  #
  # config-lowspec.xml is the confirmed-working downgraded config and
  # keeps the source <meta> GPU pins (lastvendorid/deviceid/driverversion)
  # plus forcecheckdriver/forcechecksettings=0. Blanking the pins to 0 was
  # tried and FAILED: on first launch SF2 sees "no known GPU", re-runs its
  # driver/settings autodetect, and resets antialiasing 0->5 +
  # optiontexturesizebias 8->1 (re-introducing the hang) even with
  # forcecheckdriver=0. Keeping the real pin makes SF2 see a matching GPU
  # and leave OUR low settings intact. The downside is the pin reflects the
  # build host's AMD GPU (vendorid 4098/deviceid 4372); on a *different*
  # GPU SF2 would re-detect and reset anyway, but on matching hardware --
  # the seat where the load-completes fix was user-confirmed -- the low
  # settings survive first launch.
  preRun = ''
    cfgdir="$STROM_GAMEDIR/SpellForce2"
    if [ ! -e "$cfgdir/config.xml" ]; then
      mkdir -p "$cfgdir"
      cp ${./config-lowspec.xml} "$cfgdir/config.xml"
      chmod u+w "$cfgdir/config.xml"
    fi
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Confine the pointer to the window (relative mouse mode) so RTS
      # screen-edge scrolling doesn't go erratic when the cursor leaves
      # the game window -- same as the other strategy games here.
      "--force-grab-cursor" = true;
    };
  };

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";

    # The SpellForce 2 engine predates many-core CPUs (built for <=4 cores)
    # and races its asset/scene-graph worker threads against the main loop
    # when it sees a high logical-CPU count, which on modern hosts shows up
    # as an infinite level-load hang. The unanimous community fix is to pin
    # the game to a single CPU core (Task Manager -> Set affinity -> one core
    # on Windows). taskset/numactl do not constrain Wine threads, so cap the
    # topology Wine reports instead; this makes the game see one logical CPU
    # (verified: Cpus_allowed_list=0, worker-thread count drops 38 -> 23).
    WINE_CPU_TOPOLOGY = "1:0";
  };

  meta = {
    description = "SpellForce 2 - Anniversary Edition (Grimlore/THQ Nordic 2017, GOG v2.01.85906, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "spellforce-2-anniversary-edition";
  };
}
