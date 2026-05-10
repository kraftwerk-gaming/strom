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
  # streaming). Hosted on Codeberg via the same mirror Lutris uses.
  hoodlumExe = fetchurl {
    url = "https://codeberg.org/xls69/gta_sa_largeaddress/raw/branch/main/gta_sa.exe";
    hash = "sha256-8BoAzpUPpAyh7VnfDniYSMbtz2QFRWJ0lliF0JKTQ6w=";
    name = "gta_sa.exe";
  };

  # ThirteenAG's Ultimate ASI Loader, vorbisFile.dll variant. Hijacks
  # the Vorbis OGG codec the game already loads at startup, then loads
  # any *.asi plugin from the game directory (SilentPatchSA.asi,
  # GTASA.WidescreenFix.asi, modloader.asi, ...).
  asiLoader = fetchurl {
    url = "https://github.com/ThirteenAG/Ultimate-ASI-Loader/releases/download/Win32-latest/vorbisFile-Win32.zip";
    hash = "sha256-8rUwUA6wtlB9vBJoCO84S5owQj16eEQaxzHGxMKaVP8=";
    name = "vorbisFile-Win32.zip";
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
  # on >60 FPS, fixes plane shadows, fog flicker, etc.
  silentPatch = fetchurl {
    url = "https://github.com/CookiePLMonster/SilentPatch/releases/latest/download/SilentPatchSA.zip";
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
          "$out"/{vorbisFile.dll,vorbishooked.dll,samp-license.txt}

    # Replace the stock gta_sa.exe with the HOODLUM large-address-aware
    # build (no-DVD, >2 GiB heap).
    cp -f ${hoodlumExe} "$out/gta_sa.exe"

    # ASI Loader: drop vorbisFile.dll next to gta_sa.exe.
    unzip -q -o ${asiLoader} -d "$out"

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
