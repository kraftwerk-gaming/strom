{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  unzip,
}:

let
  # GTA San Andreas PC v1.0 (2005 Rockstar). Archive holds the
  # pre-installed retail v1.0 game tree (no Hot Coffee remover, no
  # Definitive Edition, no Steam re-release — all of which break the
  # SilentPatch / Widescreen Fix / ModLoader / ASI Loader stack the
  # game effectively requires on modern hardware).
  gameSrc = fetchIpfs {
    cid = "QmdUAZBf4hyjibRYfZYXDUgGJnXotDdHN8ZsTpwwBbjpJo";
    fallbackUrl = "https://archive.org/download/gta-san-andreas_202110/GTA%20San%20Andreas.rar";
    hash = "sha256-fCRuSR/esWiHBq1EhsJGWE8U5zKQxCjod/hh/+LJcWY=";
    name = "grand-theft-auto-san-andreas-pc-1.0.rar";
  };

  # HOODLUM-patched gta_sa.exe: the original v1.0 binary modified to
  # remove the disc check and flagged large-address-aware so the engine
  # can address >2 GiB of textures (required for ModLoader / WS Fix /
  # SilentPatch to coexist without out-of-memory crashes during
  # streaming). Hosted on Codeberg via the same mirror Lutris uses. Pinned
  # to an immutable commit instead of raw/branch/main so a push to that
  # repo can't silently change the binary under us.
  hoodlumExe = fetchurl {
    url = "https://codeberg.org/xls69/gta_sa_largeaddress/raw/commit/d59292bc49d43ddcc209531620734da5a77ca5b9/gta_sa.exe";
    hash = "sha256-8BoAzpUPpAyh7VnfDniYSMbtz2QFRWJ0lliF0JKTQ6w=";
    name = "gta_sa.exe";
  };

  # ThirteenAG's Ultimate ASI Loader. Hijacks the Vorbis OGG codec the
  # game already loads at startup, then loads any *.asi plugin from the
  # game directory (SilentPatchSA.asi, GTASA.WidescreenFix.asi,
  # modloader.asi, ...). Pinned to the immutable v9.7.2 release instead of
  # the rolling Win32-latest tag (which gets force-overwritten on every
  # upstream build, drifting the hash). The loader is a single universal
  # proxy DLL shipped as dinput8.dll here; it selects its proxy target
  # from its own filename, so the buildScript renames it to vorbisFile.dll
  # (byte-identical to the old vorbisFile-Win32.zip payload, verified).
  asiLoader = fetchurl {
    url = "https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/v9.7.2/Ultimate-ASI-Loader.zip";
    hash = "sha256-DzR1izDqoO+1n3rgQQDbeJkU4aCIkbiYeLj9sYnCp8U=";
    name = "Ultimate-ASI-Loader-Win32-v9.7.2.zip";
  };

  # thelink2012's ModLoader: lets you drop .img / .txd / .dff / .ide
  # mod folders into modloader/ at runtime instead of rebuilding the
  # IMG archives. Also the de-facto loader for SilentPatchSA and the
  # WidescreenFix bundle.
  modLoader = fetchurl {
    url = "https://github.com/thelink2012/modloader/releases/download/v0.3.7/modloader.zip";
    hash = "sha256-s9AYSxgiybAonzJtiVjFaX2Dcm+shEyFr/ATcuGlIOI=";
    name = "modloader-0.3.7.zip";
  };

  # SilentPatchSA: the canonical bug-fix patch for the v1.0 binary.
  # Restores radio stations, fixes timing-dependent physics that broke
  # on >60 FPS, fixes plane shadows, fog flicker, etc. Pinned to the
  # immutable 1.1-BUILD33.1-SA tag instead of releases/latest (whose
  # SilentPatchSA.zip moves as new per-game hotfixes ship); byte-identical
  # to the previous releases/latest payload.
  silentPatch = fetchurl {
    url = "https://github.com/CookiePLMonster/SilentPatch/releases/download/1.1-BUILD33.1-SA/SilentPatchSA.zip";
    hash = "sha256-XZFenzu6txN+H7nRw/cx6JWoilAFV2SSkflpTAB+9hE=";
    name = "SilentPatchSA.zip";
  };

  # ThirteenAG's WidescreenFix: stretches HUD/menus/cutscenes to native
  # 16:9/16:10/21:9 instead of pillar-boxing 4:3 onto a wide display.
  widescreenFix = fetchurl {
    url = "https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/gtasa-wshps/GTASA.WidescreenFix.Archived.zip";
    hash = "sha256-QvyEJHVBiLM0pOn4ChQ7imkWFyqXkHclh2078tXm5hA=";
    name = "GTASA.WidescreenFix.Archived.zip";
  };

  # WSHPS: HOR+ companion to WidescreenFix. Adjusts FOV based on aspect
  # ratio so wider monitors see *more* of the world rather than a
  # zoomed-in 4:3 slice.
  wshpsAsi = fetchurl {
    url = "https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/gtasa-wshps/wshps.asi";
    hash = "sha256-CdDD+dbiYZ2F7+h7moVkq+z6g1JsOajddZM8JGGwIHU=";
    name = "wshps.asi";
  };

  # Improved Fast Loader by Link/2012: the canonical no-keypress intro
  # skip for GTA SA 1.0 US (see buildScript for the winegstreamer
  # EC_COMPLETE hang it works around). The original GTAGarage host
  # (mod 37720) is defunct; pinned to an immutable Wayback raw ('id_')
  # capture of the original gtanet CDN download. Source (MIT/public
  # domain, by the same author as ModLoader) is bundled in the zip as
  # src.zip. The .asi version-checks the exe and no-ops on anything but
  # 1.0 US, so it is inert if the base exe ever changes.
  improvedFastLoader = fetchurl {
    url = "https://web.archive.org/web/20150508104139id_/http://download.gtanet.com/gtagarage/files/37720/imfast.zip?st=Pe025nK-HZTSMM4eHwzhRw&e=1431082005";
    hash = "sha256-YFBYNDcsh+kv2IS6AK1Njy40F7MRi7pPnfzYPa96G6I=";
    name = "improved-fast-loader-imfast.zip";
  };

  # GInput (Silent/CookiePLMonster) v1.11: GTA SA's native pad support is
  # DirectInput-only with a broken fixed mapping -- modern XInput pads get
  # D-pad-only movement, the stick duplicates the D-pad, and most buttons
  # (enter vehicle, etc.) go unmapped. GInput rewrites controls onto XInput
  # so the pad maps like the console versions. Loaded as an ASI from the
  # game root by the ThirteenAG vorbisFile shim (same path as imfast.asi).
  # Blog-hosted (no GitHub release / tag); pinned by hash -- the payload is
  # stable (1.11 is the last release, unchanged since 2016).
  ginput = fetchurl {
    url = "https://silent.rockstarvision.com/uploads/GInputSA.zip";
    hash = "sha256-ttA+MyLGHto8WC3aBi81R90Gtzw/+CmO5Krw2BqewgE=";
    name = "GInputSA-1.11.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "grand-theft-auto-san-andreas";

  src = gameSrc;
  ipfsSources = [ gameSrc ];

  nativeBuildInputs = [
    unar
    unzip
  ];

  buildScript = ''
    mkdir -p "$out"

    # Extract the base v1.0 game tree. The rar's top-level layout
    # varies between releases; locate gta_sa.exe and promote that
    # directory to the output root.
    unar -f -q -o "$TMPDIR/game" "$src"
    exedir=$(find "$TMPDIR/game" -maxdepth 4 -iname 'gta_sa.exe' -printf '%h\n' | head -n1)
    if [ -z "$exedir" ]; then
      echo "gta_sa.exe not found in archive" >&2
      exit 1
    fi
    cp -r "$exedir"/. "$out"/
    chmod -R u+w "$out"

    # The base archive bundles SA-MP (San Andreas Multi Player), which
    # ships its own vorbisFile.dll / vorbishooked.dll plus samp* helper
    # binaries that we don't want pre-loaded (they hook the same Vorbis
    # entry point the ASI Loader needs). Strip them so the loader path
    # is clean for SilentPatch / WidescreenFix / ModLoader.
    rm -f "$out"/{samp.exe,samp.dll,samp_debug.exe,SAMPUninstall.exe,rcon.exe} \
          "$out"/{vorbisFile.dll,vorbishooked.dll,samp-license.txt} \
          "$out"/{samp.saa,sampgui.png}

    # Drop the repack's pre-existing generic "gta screen fix.asi": a
    # third-party resolution-forcing ASI that collides with ThirteenAG's
    # WidescreenFix + SilentPatch we install below.
    rm -f "$out/gta screen fix.asi"

    # Replace the stock gta_sa.exe with the HOODLUM large-address-aware
    # build (no-DVD, >2 GiB heap).
    cp -f ${hoodlumExe} "$out/gta_sa.exe"

    # ASI Loader: the v9.7.2 zip ships the universal loader as dinput8.dll;
    # install it as vorbisFile.dll next to gta_sa.exe (UAL picks its proxy
    # target from its own filename).
    unzip -q -o ${asiLoader} dinput8.dll -d "$out"
    mv "$out/dinput8.dll" "$out/vorbisFile.dll"

    # ModLoader: drops modloader.asi + modloader/ at the game root.
    unzip -q -o ${modLoader} -d "$out"

    # SilentPatch goes inside modloader so ModLoader handles it.
    mkdir -p "$out/modloader/SilentPatchSA"
    unzip -q -o ${silentPatch} -d "$out/modloader/SilentPatchSA"

    # Widescreen Fix is shipped as
    # GTASA.WidescreenFix/scripts/{GTASA.WidescreenFix.asi,ini} inside
    # the archived zip plus a vorbisFile.dll the bundle would otherwise
    # use as its own ASI loader. We already loaded ASI via the
    # ThirteenAG vorbisFile shim above, so only pull the .asi/.ini
    # plugin files (and skip both the bundled loader and the optional
    # modupdater.asi which would call out to the network).
    mkdir -p "$TMPDIR/wsfix" "$out/modloader/WidescreenFix"
    unzip -q -o ${widescreenFix} -d "$TMPDIR/wsfix"
    cp -f "$TMPDIR/wsfix/GTASA.WidescreenFix/scripts/GTASA.WidescreenFix.asi" \
         "$out/modloader/WidescreenFix/"
    cp -f "$TMPDIR/wsfix/GTASA.WidescreenFix/scripts/GTASA.WidescreenFix.ini" \
         "$out/modloader/WidescreenFix/"
    cp -f ${wshpsAsi} "$out/modloader/WidescreenFix/wshps.asi"

    # Improved Fast Loader (Link/2012). Skips the startup intro movies
    # WITHOUT a keypress. On Proton the PC build plays movies/Logo.mpg +
    # movies/GTAtitles.mpg through DirectShow -> winegstreamer, and the
    # engine then blocks on the DirectShow graph's EC_COMPLETE
    # (end-of-stream) event to auto-advance to the FrontEnd menu — but
    # winegstreamer never fires EC_COMPLETE for these MPEG-1 program
    # streams, so the game hangs forever on a black screen (it does not
    # crash; only a keypress dismisses it). Deleting or 0-byting the
    # .mpg files does NOT help: the engine still enters the movie-wait
    # state and waits for input. imfast.asi hooks SA's startup state
    # machine (START_GAME_AT=3) to skip the movie stage entirely so the
    # menu renders on its own. Must live in the GAME ROOT, not modloader/
    # (in modloader/ its load-last-save feature breaks). Loaded by the
    # ThirteenAG vorbisFile ASI shim installed above.
    mkdir -p "$TMPDIR/imfast"
    unzip -q -o ${improvedFastLoader} -d "$TMPDIR/imfast"
    cp -f "$TMPDIR/imfast/imfast.asi" "$out/imfast.asi"
    cp -f "$TMPDIR/imfast/imfast.ini" "$out/imfast.ini"

    # GInput: swap SA's broken native DirectInput pad handling for XInput
    # (correct console-style mapping incl. enter-vehicle, separate stick vs
    # D-pad). GInputSA.asi loads from the game root via the vorbisFile ASI
    # shim; the button-prompt .txd models merge into the game's models/ dir.
    unzip -q -o ${ginput} GInputSA.asi GInputSA.ini -d "$out"
    unzip -q -o ${ginput} 'models/*' -d "$out"
  '';

  runtime = "proton";
  executable = "gta_sa.exe";

  saveLocations = [
    "AppData/Local/modloader"
    "Documents/GTA San Andreas User Files"
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
    # vorbisFile is the ASI Loader shim; let the game-bundled DLL win
    # over Wine's own (n,b = native then builtin).
    WINEDLLOVERRIDES = "vorbisFile=n,b";
  };

  meta = {
    description = "Grand Theft Auto: San Andreas (Rockstar 2005, PC v1.0 + HOODLUM + SilentPatch + ModLoader + ThirteenAG Widescreen Fix, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "grand-theft-auto-san-andreas";
  };
}
