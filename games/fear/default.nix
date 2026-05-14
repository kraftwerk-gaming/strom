{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # F.E.A.R. Platinum Collection: base game (Monolith 2005, Lithtech
  # Jupiter EX) plus Extraction Point (TimeGate 2006) and Perseus
  # Mandate (TimeGate 2007). GOG offline installer v2.1.0.7 (build
  # 80111), Inno Setup 5.6.2 unicode. The archive is a single rar
  # that wraps the three setup binaries plus a Bonus/ tree of zips
  # (alma_live, directors_commentary, making_of, manuals,
  # panics_machinima, wallpaper); only the setup .exe/.bin trio is
  # needed to install. Innoextract --gog handles the multi-part
  # installer the same way painkiller and homeworld do.
  src = fetchIpfs {
    cid = "QmbF1m9dXiSvHXTQgcK45s1zkEtJ3HaJShLkg9o17CGFbg";
    fallbackUrl = "https://archive.org/download/f.-e.-a.-r.-platinum-collection/F.E.A.R.%20-%20Platinum%20Collection.rar";
    hash = "sha256-X5xPjbrnuYN7h8ockC6VD9K0HO4/4hNlrePvf1J16E0=";
    name = "fear-platinum.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "fear";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  # The rar holds five entries at the root:
  #   setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111).exe
  #   setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111)-1.bin
  #   setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111)-2.bin
  #   setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111)-3.bin
  #   Bonus/{alma_live,directors_commentary,making_of,manuals,
  #          panics_machinima,wallpaper}.zip
  #
  # Innoextract reads the multi-part installer when the .exe and the
  # three -N.bin segments sit side-by-side. The InnoSetup script
  # places the base F.E.A.R. (FEAR.exe, FEAR.Arch00 .. FEAR_8.Arch00,
  # FEARA/E/L.Arch00 region/audio/locale packs) and the Lithtech
  # engine DLLs (binkw32, dxwrapper, d3d9 proxy, dinput8, eax,
  # GameDatabase, LTMemory, MFC71, msvcp/msvcr71, EngineServer,
  # SndDrv, StringEditRuntime) at the install root, with the two
  # expansions self-contained under FEARXP/ and FEARXP2/.
  #
  # We drop the InnoSetup-internal/setup-only trees after extract:
  #   __redist/   -- bundled DirectX 9/10/11 redist cabs and VC++
  #                  runtimes; not consumed at game runtime, only by
  #                  the installer wizard. DXVK supplies d3d9 under
  #                  Proton.
  #   __support/  -- SecuROM relic (GOG is DRM-free; the dat/exe sit
  #                  here as installer artefacts only).
  #   commonappdata/  -- ALL USERS template the installer copies into
  #                  ProgramData on Windows. We never run the wizard.
  #   tmp/        -- installer slideshow assets.
  #   movies/     -- BONUS director's-commentary / making-of / alma
  #                  videos that aren't loaded by the engine (the
  #                  engine's intro/cutscene .bik streams live inside
  #                  the .Arch00 archive packs). 1.5 GiB of dead
  #                  weight on disk if kept.
  #   app/        -- just a goggame icon and webcache.zip; the actual
  #                  game payload sits at the install root, not under
  #                  {app}/.
  #   Bonus/      -- the rar's outer bonus tree; the trio above plus
  #                  this is the full reason we --no-include-prefix
  #                  via unar's specific-file selection (Bonus/ never
  #                  reaches $TMPDIR).
  buildScript = ''
    mkdir -p "$TMPDIR/rar" "$out"
    # Extract just the four installer files; Bonus/*.zip stays in the
    # rar. unar -D suppresses the auto-wrapper dir.
    unar -D -o "$TMPDIR/rar" "$src" \
      'setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111).exe' \
      'setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111)-1.bin' \
      'setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111)-2.bin' \
      'setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111)-3.bin'

    cd "$TMPDIR/rar"
    innoextract --gog -d "$out" \
      'setup_f.e.a.r._platinum_collection_2.1.0.7_gog_v1_(80111).exe'

    # Drop installer-only trees that bloat the closure without
    # contributing to runtime.
    chmod -R u+w "$out"
    rm -rf \
      "$out/__redist" \
      "$out/__support" \
      "$out/commonappdata" \
      "$out/tmp" \
      "$out/movies" \
      "$out/app"
    # GOG metadata stubs (Galaxy-side; not loaded by FEAR.exe).
    rm -f "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/webcache.zip
  '';

  runtime = "proton";
  # FEAR.exe at the install root is the base-game launcher; the
  # in-engine main menu lets the user switch campaigns but each
  # expansion has its own .exe under FEARXP/ and FEARXP2/. The
  # canonical entry point is the original 2005 release (Monolith
  # build), which is what the package request asks for.
  executable = "FEAR.exe";

  # Lithtech Jupiter EX accepts +convars on the cmdline that bypass
  # the in-engine display-mode probe (same trick used for the older
  # Lithtech 1.x engine in no-one-lives-forever). Without an explicit
  # mode the engine enumerates D3D9 adapter modes, picks one that DXVK
  # then refuses, and loops "Reinitializing renderer" forever. Locking
  # 1920x1080x32 windowed (gamescope handles the actual fullscreen
  # surface) makes the first mode-set succeed and the loop never
  # starts.
  executableArgs = [
    "+screenwidth"
    "1920"
    "+screenheight"
    "1080"
    "+bitdepth"
    "32"
    "+windowed"
    "1"
    "+disablevsync"
    "1"
  ];

  saveLocations = [
    # F.E.A.R. writes Documents/Monolith Productions/FEAR (settings.cfg,
    # save slots) under steamuser; Extraction Point and Perseus
    # Mandate use TimeGate Studios subtrees. Relocate them all so a
    # prefix wipe doesn't take user progress.
    "Documents/Monolith Productions/FEAR"
    "Documents/TimeGate Studios/FEARXP"
    "Documents/TimeGate Studios/FEARXP2"
  ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  env = {
    # SteamAppId 21090 == F.E.A.R. on Steam; protonfixes keys on this
    # if we ever need them, and games that probe Steam env vars find
    # a coherent appid.
    STEAM_COMPAT_APP_ID = "21090";
    SteamAppId = "21090";
    # The Lithtech Jupiter EX engine is 32-bit and benefits from the
    # large-address-aware patch on level loads.
    WINE_LARGE_ADDRESS_AWARE = "1";
    # The GOG installer ships a d3d9.dll proxy that loads
    # dxwrapper.dll (Elisha Riedlinger build) next to FEAR.exe.
    # Stacking the native proxy on top of dxwrapper on top of DXVK's
    # d3d9 produced a triple wrapper chain that Lithtech Jupiter EX
    # could never reconcile: the engine kept re-creating the
    # IDirect3DDevice9 (see dxwrapper-fear.log:
    # m_IDirect3DDevice9Ex::~m_IDirect3DDevice9Ex followed by another
    # Direct3DCreate9 redirect within milliseconds) and the main menu
    # cycled "Reinitializing renderer" indefinitely. Force d3d9 to the
    # wine builtin (DXVK) and explicitly disable dxwrapper so neither
    # the bundled proxy nor the wrapper loads. DXVK handles 1080p,
    # FOV widescreen needs no special hook at native 16:9, and
    # binkw32 / dinput8 / eax remain native (the engine's bink player
    # and EAX HRTF code only work with the shipped DLLs).
    WINEDLLOVERRIDES = "d3d9=b;dxwrapper=;dinput8,eax,binkw32=n,b";
  };

  meta = {
    description = "F.E.A.R. Platinum Collection (Monolith 2005 + TimeGate 2006/2007, GOG v2.1.0.7, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "fear";
  };
}
