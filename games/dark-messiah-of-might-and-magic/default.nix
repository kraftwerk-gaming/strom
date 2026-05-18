{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Pre-baked Dark Messiah of Might and Magic post-install tree, sourced
  # from the ElAmigos repack. The upstream .rar is an Inno Setup loader
  # plus three FreeArc payloads (cls-srep/cls-lolz/cls-bpk codec stack)
  # that only decode through Win32 ISDone.dll/unarc.dll, and innoextract
  # refuses the customised Inno variant. The repack itself runs
  # /SILENT /SUPPRESSMSGBOXES end-to-end under wine in ~90 s on a host
  # with a working FHS, which is well within the in-FOD install budget,
  # but the sandboxed FOD path needs a 32-bit FHS to host proton's wine
  # preloader and an Xvfb stub for the mascot dialog. To keep the recipe
  # tight we instead bake the install once on the host (silent flags,
  # no user interaction) and pin the resulting tree as a deterministic
  # tar.zst -- consumers just fetchIpfs + tar.
  src = fetchIpfs {
    cid = "QmSVGKyNwZmDQk3LHuLWjdjVrb58fP6MxMEBo2c8ExEGqi";
    hash = "sha256-GKJN789VcebXFtX7bDX2BLlE2eXEkeQ1U89VxVSXsM0=";
    name = "dark-messiah-mm.tar.zst";
  };

  # Canonical english Dark Messiah keybinds, used as cfg/config_default.cfg
  # and as the fresh-prefix cfg/config.cfg seed. The ElAmigos repack ships
  # the engine GCFs but strips the per-language mm_<lang>.gcf overlays
  # (only mm_engine_pub.gcf et al. exist), so the engine's `%language%`
  # search-path expansion silently fails and falls back to whatever
  # config_default.cfg ships inside mm_engine_pub.gcf -- which the repack
  # ALSO populates with the AZERTY bind block (z=+forward, q=+moveleft,
  # w=+leanleft) because the repack was built from the french MULTi7 SKU.
  # Source's loose-file search beats GCF, so dropping a known-good english
  # config_default.cfg into mm/cfg/ takes priority on every fresh-prefix
  # autoconfig pass.
  configDefaultCfg = ''
    unbindall
    bind "TAB" "togglecharsheet"
    bind "ESCAPE" "cancelselect"
    bind "SPACE" "+jump"
    bind "'" "toggleconsole"
    bind "+" "sizeup"
    bind "-" "sizedown"
    bind "1" "usebelt1"
    bind "2" "usebelt2"
    bind "3" "usebelt3"
    bind "4" "usebelt4"
    bind "5" "usebelt5"
    bind "6" "usebelt6"
    bind "7" "usebelt7"
    bind "8" "usebelt8"
    bind "9" "usebelt9"
    bind ";" "+mlook"
    bind "=" "sizeup"
    bind "[" "mminventory_previtem"
    bind "]" "mminventory_nextitem"
    bind "`" "toggleconsole"
    bind "w" "+forward"
    bind "a" "+moveleft"
    bind "s" "+back"
    bind "d" "+moveright"
    bind "q" "+leanleft"
    bind "e" "+use"
    bind "f" "+kick"
    bind "r" "+zoom"
    bind "v" "+xana"
    bind "x" "+leanright"
    bind "o" "mm_objectives_show"
    bind "ALT" "+speed"
    bind "CTRL" "+duck"
    bind "SHIFT" "+sprint"
    bind "F6" "save quick"
    bind "F9" "load quick"
    bind "INS" "+klook"
    bind "HOME" "screenshot"
    bind "END" "centerview"
    bind "MWHEELDOWN" "mm_nextitem"
    bind "MWHEELUP" "mm_previtem"
    bind "MOUSE1" "+attack"
    bind "MOUSE2" "+attack2"
    bind "PAUSE" "pause"
    cl_language "english"
    cc_lang ""
    sensitivity "5"
    crosshair "1"
    cl_mouselook "1"
    volume "1"
    bgmvolume "1"
    suitvolume "0.25"
    voice_enable "1"
    voice_scale "1"
    name "unnamed"
  '';

  # Autoexec runs after config.cfg on every launch; pin the engine
  # language convar so the UI/sound-pack picker can't drift back to
  # french if something else (locale heuristic, leftover savefile) tries
  # to override it.
  autoexecCfg = ''
    cl_language "english"
    cc_lang ""
  '';

  # scripts/kb_act.lst is the Source controls-menu MANIFEST, not a
  # binding file. The columns are "<activity>" "<localization_token>"
  # (the second column references mm_<lang>.txt strings the controls
  # UI displays as row labels). Round 4 mis-read this as a key->action
  # binding table, shipped "<key>" "<activity>" instead, and broke the
  # controls UI: with no valid leading +activity tokens the controls
  # tab fails to enumerate and renders nothing. Replace with the
  # canonical Dark Messiah layout (matches the KingDavidW
  # DarkMessiah-Coop-Mod-Files reference, which is in turn a verbatim
  # copy of the retail mm_engine_pub.gcf kb_act.lst).
  #
  # Actual key bindings come from cfg/config_default.cfg (round 3) and
  # the AZERTY-config.cfg cleanup in preRun, NOT from this file.
  kbActLst = ''
    "blank"			"=========================="
    "blank"			"#menu_controls_movement"
    "blank"			"=========================="
    "+forward"				"#menu_controls_forward"
    "+back"					"#menu_controls_back"
    "+moveleft"				"#menu_controls_moveleft"
    "+moveright"			"#menu_controls_moveright"
    "+speed"             	"#menu_controls_speed"
    "+jump"					"#menu_controls_jump"
    "+duck"					"#menu_controls_duck"
    "+sprint"					"#menu_controls_sprint"
    "+leanleft"					"#menu_leanleft"
    "+leanright"					"#menu_leanright"
    "blank"			"=========================="
    "blank"			"#menu_controls_combatmagic"
    "blank"			"=========================="
    "+attack"	"#menu_controls_attack"
    "+attack2"	"#menu_controls_attack2"
    "+kick"	"#menu_controls_kick"
    "+zoom"		"#menu_controls_zoom"
    "+xana"		"#menu_controls_xana"
    "blank"			"=========================="
    "blank"			"#menu_controls_misc"
    "blank"			"=========================="
    "togglecharsheet" "#menu_controls_togglecharsheet"
    "+use" "#menu_controls_use"
    "usebelt1" "#menu_controls_usebelt1"
    "usebelt2" "#menu_controls_usebelt2"
    "usebelt3" "#menu_controls_usebelt3"
    "usebelt4" "#menu_controls_usebelt4"
    "usebelt5" "#menu_controls_usebelt5"
    "usebelt6" "#menu_controls_usebelt6"
    "usebelt7" "#menu_controls_usebelt7"
    "usebelt8" "#menu_controls_usebelt8"
    "usebelt9" "#menu_controls_usebelt9"
    "mm_previtem" "#menu_controls_previtem"
    "mm_nextitem" "#menu_controls_nextitem"
    "mm_objectives_show" "#menu_controls_mm_objectives_show"
    "blank"			"=========================="
    "blank"			"#menu_controls_multiplayer"
    "blank"			"=========================="
    "say"	"#menu_controls_chat"
    "+voicerecord"	"#menu_controls_voice"
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dark-messiah-of-might-and-magic";

  inherit src;
  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  # After untar, overlay a loose mm/cfg/{config_default,autoexec}.cfg so
  # Source's loose-file-beats-GCF search order picks english binds on
  # every fresh autoconfig. The repack's tar has no mm/cfg/ directory of
  # its own (verified: empty), so we create it cleanly.
  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
    mkdir -p "$out/mm/cfg" "$out/mm/scripts"
    cp ${pkgs.writeText "config_default.cfg" configDefaultCfg} "$out/mm/cfg/config_default.cfg"
    cp ${pkgs.writeText "autoexec.cfg" autoexecCfg} "$out/mm/cfg/autoexec.cfg"
    # Override scripts/kb_act.lst (loose beats GCF) so the engine's
    # activity-binding autoconfig reads English WASD instead of the
    # AZERTY layout baked into mm_engine_pub.gcf. Also override the
    # demo variant in case the engine fallback-mounts it.
    cp ${pkgs.writeText "kb_act.lst" kbActLst} "$out/mm/scripts/kb_act.lst"
    cp ${pkgs.writeText "kb_act_demo.lst" kbActLst} "$out/mm/scripts/kb_act_demo.lst"
    # Pin gameinfo.txt's %language% expansion to english so the engine's
    # per-language GCF search path (mm/mm_%language%.gcf::mm) can never
    # land on a french/spanish/etc. variant if such a GCF appears in a
    # later repack rev. The repack ships no mm_<lang>.gcf at all so this
    # is currently a no-op, but it removes one route to regression.
    sed -i 's|mm/mm_%language%\.gcf|mm/mm_english.gcf|' "$out/mm/gameinfo.txt"
  '';

  runtime = "proton";
  # Source-engine singleplayer entry; bin/launcher.dll boots the
  # dark-messiah singleplayer module.
  executable = "mm.exe";
  # Force 1920x1080 from the engine itself: first-launch config.cfg defaults
  # to a low fallback resolution, and the user wipes the wineprefix between
  # tests so a one-shot cfg seed wouldn't stick. The launch flags hit the
  # Source engine before it reads cfg/video.txt and pin the mode regardless
  # of saved state.
  #
  # `-language english` forces the engine's `%language%` GCF substitution
  # (gameinfo.txt: `mm/mm_%language%.gcf::mm`) to english, independent of
  # the Steam-language registry. Source 2006 still consults
  # HKCU\Software\Valve\Steam\Language for UI strings even when the
  # GCFs are pinned, so the language registry seed in preRun is the
  # primary fix; this flag is belt-and-suspenders for the GCF mount.
  executableArgs = [
    "-w"
    "1920"
    "-h"
    "1080"
    "-language"
    "english"
  ];

  # Source 2006's launcher.dll picks the UI / keybind-label language from
  # HKCU\Software\Valve\Steam\Language (see
  # https://www.pcgamingwiki.com/wiki/Dark_Messiah_of_Might_and_Magic --
  # "the only way to set its language is by changing the language of Steam
  # itself"). On a fresh proton prefix that key is absent and the engine
  # falls back to a locale heuristic that, with the ElAmigos MULTi7 repack's
  # bundled GCFs, lands on russian -- which renders the keybind menu in
  # Cyrillic and is what the user perceives as a "russian keyboard layout"
  # (xkb is already pinned to us via gamescope.env). Seed the key before
  # mm.exe spawns; bootstrap user.reg first because proton creates it only
  # AFTER preRun on a virgin prefix (see strom feedback note
  # `prerun_userreg_bootstrap`).
  preRun = ''
    PFX="$STROM_COMPATDATA/0/pfx"
    USERREG="$PFX/user.reg"
    mkdir -p "$PFX"
    if [ ! -f "$USERREG" ]; then
      printf 'WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\.Default\n\n' > "$USERREG"
    fi
    if ! grep -q '^\[Software\\\\Valve\\\\Steam\]' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Software\\\\Valve\\\\Steam] %s\n' "$TS"
        printf '"Language"="english"\n'
      } >> "$USERREG"
    fi
    if ! grep -q '^\[Software\\\\Valve\\\\Source\\\\mm\\\\Settings\]' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Software\\\\Valve\\\\Source\\\\mm\\\\Settings] %s\n' "$TS"
        printf '"Language"="english"\n'
      } >> "$USERREG"
    fi

    # Pin Windows locale + keyboard layout to en-US/us so the Source engine's
    # GetUserDefaultLangID() locale heuristic (which fires when a user.reg
    # exists but the per-game Language key was added late) lands on english.
    # Round 2's bare Software\Valve\Steam seed left these at the wine defaults
    # which on this host evaluated to fr_FR, hence the user's AZERTY binds.
    if ! grep -q '^\[Control Panel\\\\International\] ' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Control Panel\\\\International] %s\n' "$TS"
        printf '"Locale"="00000409"\n'
        printf '"LocaleName"="en-US"\n'
        printf '"sLanguage"="ENU"\n'
      } >> "$USERREG"
    fi
    if ! grep -q '^\[Control Panel\\\\International\\\\Geo\] ' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Control Panel\\\\International\\\\Geo] %s\n' "$TS"
        printf '"Nation"="244"\n'
      } >> "$USERREG"
    fi
    if ! grep -q '^\[Keyboard Layout\\\\Preload\] ' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Keyboard Layout\\\\Preload] %s\n' "$TS"
        printf '"1"="00000409"\n'
      } >> "$USERREG"
    fi

    # Earlier rounds shipped a loose mm/cfg/config_default.cfg in the
    # nix-store data layer so Source's loose-file-beats-GCF search would
    # pick up english bindings on every fresh autoconfig. That fails in
    # practice: the fuse-overlayfs upper layer carries a `.wh..wh..opq`
    # opaque-marker on mm/cfg/ (the engine or proton creates the dir on
    # first launch, which makes overlayfs hide the lower layer entirely),
    # so the shipped config_default.cfg never reaches the engine and the
    # autoconfig pass regenerates an AZERTY config.cfg from in-GCF
    # defaults instead. Verified live in
    # ~/.strom/dark-messiah-of-might-and-magic/mm/cfg/: only .wh..wh..opq
    # + three azerty-backup.* files, no config_default.cfg.
    #
    # Skip the regenerate path entirely: write a known-good english WASD
    # config.cfg directly into the user's overlay whenever it is missing
    # or carries the AZERTY signature (z=+forward, q=+moveleft,
    # w=+leanleft). Source treats config.cfg as the saved-state snapshot
    # and will not overwrite it from defaults if it parses cleanly, so
    # one good seed per fresh prefix is enough -- subsequent launches
    # leave user rebinds alone (the AZERTY signature only matches an
    # engine-generated layout, not anything a user would intentionally
    # save).
    CFG="$STROM_GAMEDIR/mm/cfg/config.cfg"
    mkdir -p "$STROM_GAMEDIR/mm/cfg"
    if [ ! -f "$CFG" ] || grep -Eq '^bind "(z" "\+forward|q" "\+moveleft|w" "\+leanleft)"' "$CFG"; then
      [ -f "$CFG" ] && mv "$CFG" "$CFG.azerty-backup.$(date +%s)"
      cp ${pkgs.writeText "config.cfg" configDefaultCfg} "$CFG"
      chmod u+w "$CFG"
    fi
  '';

  saveLocations = [
    # Source writes savegames/.cfg under My Documents on Wine.
    "Documents/Dark Messiah Might and Magic Single Player"
  ];

  env = {
    # Source 2006 is 32-bit; large-address-aware avoids the 2 GiB
    # virtual-address ceiling on the bigger levels.
    WINE_LARGE_ADDRESS_AWARE = "1";
    STEAM_COMPAT_APP_ID = "2100";
    SteamAppId = "2100";
    # Pin the host locale that wine and the Source engine inherit. Must be
    # set here (default.nix env, reaches the proton wrapper before wine
    # initialises) rather than in preRun, which fires after wine has
    # already cached GetUserDefaultLangID() from the host LANG.
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
    # Force US qwerty inside gamescope's nested xwayland. v1 of this fix
    # ran `setxkbmap -display $DISPLAY us` in preRun, but $DISPLAY there
    # is the OUTER host X11 — gamescope spawns its own nested Xwayland
    # whose xkb layout is sourced from XKB_DEFAULT_LAYOUT at startup, so
    # the outer-X setxkbmap never reached the display the Source engine
    # actually connects to. xkeyboard-config's XKB_DEFAULT_* env vars are
    # read by libxkbcommon when gamescope initialises the nested seat;
    # exporting them in the gamescope wrapper's own preHook env (i.e.
    # before `exec gamescope`) is the upstream-blessed workaround for
    # ValveSoftware/gamescope#203.
    env = {
      XKB_DEFAULT_LAYOUT = "us";
      # Empty variant: gamescope 3.16.7+ segfaults on common values like
      # `qwerty`; the upstream default (no variant) is what we want.
      XKB_DEFAULT_VARIANT = "";
    };
  };

  meta = {
    description = "Dark Messiah of Might and Magic (Arkane 2006, Source engine, ElAmigos repack, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dark-messiah-of-might-and-magic";
  };
}
