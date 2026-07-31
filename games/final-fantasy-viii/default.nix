{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  p7zip,
  unzip,
  binutils,
  libarchive,
  runCommandLocal,
  python3,
}:

let
  # Ragnarok Rebalancing Mod v1.2.3 (Callisto), the 2013-Steam build.
  #
  # The most popular FF8 mod by a wide margin -- 874 replies on its qhimm
  # thread against 139 for the next gameplay mod (FFVIII Crystal) and 112
  # for the one after (New Threat), and the one entry HobbitInstaller's
  # catalogue ships under Gameplay for this release. Playtested start to
  # finish by its author.
  #
  # Two difficulty variants ship in the same download and differ only in
  # these six files, so they are a `ragnarokMode` choice rather than two
  # packages.
  #
  # No source repository exists: it is distributed as Google Drive zips
  # from qhimm topic 18404, and the file is a RAR despite the .zip name.
  # `fallbackUrl` is that Drive link, which is unstable but the only
  # source and doubles as provenance; the CID is what the build actually
  # resolves. NOTE p7zip's build cannot read RAR5, hence libarchive.
  ragnarokSrc = fetchIpfs {
    cid = "QmSNStGCqEpiK4zVxzZXfg8pFq4N5NQ14HA4QFfYZEnUDN";
    fallbackUrl = "https://drive.google.com/uc?id=1_3xRIFbvnnBJWS7S9npqwnA1T3Q-XHcQ";
    hash = "sha256-Cw5wKEFGRz1GnxxO+MymlmQr33qO8wbIyOWW4u2w69M=";
    name = "ragnarok-mod-v1.2.3-steam-2013.rar";
  };

  # Project the chosen variant into a tree shaped like the game root, so
  # it can be stacked as an overlay lower without re-extracting the 3.7 GB
  # base. The archive double-nests its own directory name, hence the glob.
  mkRagnarok =
    mode:
    runCommandLocal "ff8-ragnarok-1.2.3-${mode}" { nativeBuildInputs = [ libarchive ]; } ''
      mkdir -p "$out/Data/lang-en" unpacked
      bsdtar -xf ${ragnarokSrc} -C unpacked
      src=$(echo unpacked/*/*/"${
        if mode == "lionheart" then "Lionheart" else "Standard"
      } Mode files"/lang-en)
      test -d "$src" || { echo "ragnarok: variant tree not found: $src" >&2; exit 1; }
      cp "$src"/*.fi "$src"/*.fl "$src"/*.fs "$out/Data/lang-en/"

      # The other half of the mod: a Hext patch list for the things the
      # data files cannot express (ATB filling speed, the 255% hit-rate
      # removal, Protect/Shell reduction, the Vit-0 change). It only takes
      # effect with `ffnx = true`; without FFNx nothing reads it.
      #
      # The directory is FFNx's, not ours: it composes
      # hext/ff8/<variant> from the DETECTED executable
      # (cfg.cpp:389-393), and this tree's exe reports
      # VERSION_FF8_12_US_NV -- which is what every English Steam 2013
      # install reports, since FFNx's version table only knows the 1.2
      # lineage and flags the Steam build separately via af3dn.p. So
      # en_nv IS the Steam-2013 directory, and a mod written for Steam
      # 2013 belongs in it. Ragnarok's own instructions target the Steam
      # release (via Roses and Wine, whose flat RaW/GLOBAL/Hext FFNx's
      # hext/ replaces).
      #
      # Placing it wrongly is recoverable, not destructive: Hext patches
      # are applied to the RUNNING process (VirtualProtect + memcpy_code
      # in FFNx's hext.cpp:185,203), never to the file, and the game tree
      # is a read-only store path. A mismatch crashes or no-ops; it cannot
      # damage the installation.
      mkdir -p "$out/hext/ff8/en_nv"
      hext=$(echo unpacked/*/*/Ragnarok_mod.txt)
      test -s "$hext" || { echo "ragnarok: Hext patch not found" >&2; exit 1; }
      cp "$hext" "$out/hext/ff8/en_nv/"

      # Every archive the mod replaces must be present, or the engine
      # silently mixes modded and stock data.
      for f in battle field main menu; do
        for ext in fi fl fs; do
          test -s "$out/Data/lang-en/$f.$ext" \
            || { echo "ragnarok: missing $f.$ext" >&2; exit 1; }
        done
      done
    '';

  # Texture packs from the Tsunamods catalogue, which is where the FF8
  # graphics scene actually lives. Every one of them -- like every mod in
  # that catalogue -- ships as a .7z wrapping a single .iroj, the container
  # format 7th Heaven and its FF8 fork Junction VIII use, so they are
  # unusable as plain overlay lowers until unpacked. ./iro-extract.py does
  # that (format ported from Junction VIII's AppWrapper/IrosArc.cs), which
  # is what makes these installable without a Windows GUI.
  #
  # These are texture replacements: they add files under mods/textures/ and
  # touch none of the Data/lang-en archives, so they compose freely with
  # each other AND with `ragnarok`. Rebalance mods are the opposite -- see
  # the ragnarok option.
  #
  # URLs are the catalogue's own (gp-mc.net), pinned by hash. Unlike the
  # game asset these are small enough and stable enough for plain fetchurl,
  # matching how games/grand-theft-auto-san-andreas pins its mods.
  texturePacks = {
    world = {
      label = "Horizon Pack Plus v2.4 -- world map and town textures";
      inner = "horizonpack.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/horizonpack.7z";
        hash = "sha256-JuFjYSZmNIGKQjJhEZ7Dgojm/H9Xwfhi5m03IRGAtAI=";
      };
    };
    models = {
      label = "Poly-UP v4.5 -- character models and textures";
      inner = "poly_up.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/chump/poly_up.7z";
        hash = "sha256-lyj4Ziws2Ig+YH/zv6Y5DinduMVAuUEfy2fcX4UgxVs=";
      };
    };
    enemies = {
      label = "Lunar Cry Plus v4.4 -- enemy textures";
      inner = "lunarcry.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/lunarcry.7z";
        hash = "sha256-7/Tjfcsa4Qo3JPBMmx94sbClfoCHEkSaC0DXDHWkkjc=";
      };
    };
    battles = {
      label = "BattlefieldPack Plus v2.2 -- battlefield textures";
      inner = "battlefieldpack.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/battlefieldpack.7z";
        hash = "sha256-CJC/LGcfA7lttZY82ywyyjLWLj6r3j+8NTy9oG1z/a4=";
      };
    };
    gfs = {
      label = "ProjectHELLFIRE Plus v2.5 -- Guardian Force textures";
      inner = "ph.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/ph.7z";
        hash = "sha256-RBCzQNv6O745/WIf5LUBoljx7SfkEHfOBuWgqMiyV9g=";
      };
    };
    characters = {
      label = "Rebirth Flame Plus v2.0 -- character textures";
      inner = "flame_rebirth_plus.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/chump/flame_rebirth_plus.7z";
        hash = "sha256-IqvoJeKt74idKfQe0hgA/Wk9BQg1Zlk5l0kKjVCg6tg=";
      };
    };
    spells = {
      label = "Hit-J Plus v2.1 -- spell and effect textures";
      inner = "hitj.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/chump/hitj.7z";
        hash = "sha256-bP1/yiIIROhqdXeVa9aKht/R+Yj6KCXKL+dL10Fy4Ww=";
      };
    };
    battleModels = {
      label = "Skin-RF v1.62 -- battle model textures";
      inner = "skin-RF.iroj";
      src = fetchurl {
        url = "https://www.gp-mc.net/mcindus/chump/skin-RF.7z";
        hash = "sha256-dtV8eoL9W57Sc+tsL0AwGAV7pTosVRgjVshF2viEMxM=";
      };
    };
  };

  # Field backgrounds are a separate category from everything above, and
  # the distinction is the whole reason this option exists. The eight packs
  # ship mods/Textures/field/**model** -- the character models standing in
  # a field. The pre-rendered room art itself lives in field.fs and FFNx
  # overrides it at mods/Textures/field/mapdata/<map>/<map>.dds (its
  # docs/ff8/mods/external_textures.md, "Field / Maps / One texture per
  # map"). No pack above writes a single mapdata path, which is why rooms
  # stay blurry however many of them you enable.
  #
  # This is the only free, maintained, FFNx-native field pack in
  # existence. The alternatives were checked and rejected: AngelWing
  # Ultima is the best-looking and is Patreon-only, never publicly
  # released; the free AngelWing v3.0 ships 512x1024 tiles for Tonberry,
  # where FFNx needs squares (its background.cpp works at
  # TEXTURE_WIDTH_BPP4 x TEXTURE_HEIGHT = 256x256), so it does not load at
  # all; Project Eden's only downloads are goo.gl links, dead since Google
  # retired the shortener in 2025; GUM is a 2019 pre-alpha, also Tonberry.
  #
  # It is INCOMPLETE and honestly so: 157 of 877 maps, Balamb Garden and
  # Ifrit's Cave finished. Outside those the rooms are still vanilla, so
  # the game looks inconsistent -- which is why this is opt-in separately
  # from `textures` rather than folded into it.
  #
  # Only _FBG_4XSHARP is taken. The archive also holds ~1.2 GiB of UI
  # themes, cursors and controller glyphs, plus FIELD_MODELS/HIGH_POLY
  # whose own README says high-poly field models were once withdrawn "to
  # prevent crashes and artifacts". Those are not what this option is for,
  # and 12 of the UI ModFolder elements carry no ActiveWhen at all, so
  # mod.xml gating cannot exclude them -- hence the explicit --only.
  fieldBackgroundPack = {
    label = "AxlRose's WIP v2026.0705 -- 4x field backgrounds, 157 of 877 maps";
    inner = "AxlRoseWIP.iroj";
    only = [ "_FBG_4XSHARP" ];
    src = fetchurl {
      url = "https://www.gp-mc.net/ff8/tsunamods/AxlRoseWIP.7z";
      hash = "sha256-PIa8J0pPMF1f9zsggGcoJBFwRCkw0/39Rg5y6ZFGCrw=";
    };
  };

  # Priority order for the packs, highest first, because they DO overlap:
  # 118 of the 1392 files collide, essentially all of them battle
  # character textures shipped by both Poly-UP (which bundles matching
  # models AND textures, v4.5) and the older Rebirth Flame Plus (textures
  # only, v2.0). Overlay lowers are first-wins, so leaving this to the
  # attribute set's alphabetical order would silently let the older
  # textures land on the newer models. Poly-UP wins instead; the remaining
  # packs cover disjoint surfaces and their order is immaterial.
  texturePackOrder = [
    "models"
    "characters"
    "battleModels"
    "gfs"
    "spells"
    "enemies"
    "battles"
    "world"
  ];

  # Unwrap .7z -> .iroj -> plain tree. Folder selection inside the archive
  # comes from the mod's own mod.xml defaults; ./iro-extract.py resolves
  # each `<ModFolder ActiveWhen="var = value">` against the matching
  # `<ConfigOption><Default>`, which is what Junction VIII's UI would
  # otherwise ask the user about.
  mkTexturePack =
    key: pack:
    runCommandLocal "ff8-texturepack-${key}"
      {
        nativeBuildInputs = [
          p7zip
          python3
        ];
      }
      ''
        7z x -y -bso0 -bsp0 -o"$TMPDIR/pack" ${pack.src}
        mkdir -p "$out"
        python3 ${./iro-extract.py} "$TMPDIR/pack/${pack.inner}" "$out" \
          ${lib.concatMapStringsSep " " (f: "--only ${lib.escapeShellArg f}") (pack.only or [ ])}

        # Normalise to the casing FFNx actually reads. Its mod_path is
        # "mods/Textures" (FFNx.toml:488) and packs are inconsistent about
        # it -- Horizon Pack emits mods/textures, Poly-UP mods/Textures.
        # Windows would not care; a case-sensitive overlay would leave two
        # sibling directories and wine would resolve only one of them,
        # silently hiding the other pack's textures.
        if [ -d "$out/mods/textures" ]; then
          mkdir -p "$out/mods/Textures"
          cp -rn "$out/mods/textures"/. "$out/mods/Textures"/
          rm -rf "$out/mods/textures"
        fi

        # Anything outside mods/ is a loose replacement for a file the
        # engine would otherwise read from an .fs archive -- Poly-UP ships
        # FIELD/model/main_chr/*.mch that way. FFNx reads those from
        # direct_mode_path (FFNx.toml:530, "if FF8 is looking for
        # .../FIELD/... in field.fs, open direct/FIELD/... if it exists"),
        # so that is where they go.
        for entry in "$out"/*; do
          base=$(basename "$entry")
          case "$base" in
            mods | direct | hext) continue ;;
          esac
          mkdir -p "$out/direct"
          mv "$entry" "$out/direct/"
        done

        test -d "$out/mods/Textures" || test -d "$out/direct" || {
          echo "${key}: produced neither mods/Textures nor direct/" >&2
          exit 1
        }
      '';

  texturePackLowers = map (key: mkTexturePack key texturePacks.${key}) texturePackOrder;

  # Music. The 2013 release is the 2000 PC port's audio verbatim: 91
  # DirectMusic .sgt sequences rendered through an 8 MB DLS instrument bank
  # in Data/Music/dmusic. That is a General-MIDI-class software synth, and
  # it is the biggest fidelity gap left in this package -- audibly worse
  # than the PSX original it was derived from, which is why swapping it is
  # worth 14 MB.
  #
  # The 19 Data/Music/stream/*.wav ambiences and eyes_on_me.wav are already
  # 16-bit PCM, so replacing THOSE with lossy files is a downgrade. FFNx
  # keeps them: .wav-backed tracks fall back to the original file when no
  # external one exists (music.cpp:292-299). Only the sequenced half is
  # replaced here.
  #
  # Note how FFNx names tracks, because it decides what a pack must be
  # called: ff8_format_midi_name (music.cpp:148-160) cuts everything up to
  # and including the first "-" off the .sgt filename, so 005s-battle.sgt
  # is looked up as "battle". Both packs below already ship that naming.
  #
  # The hazard to design around: with use_external_music on, FFNx replaces
  # play_midi outright (music.cpp:1213), so a sequenced track with no
  # external file plays SILENCE -- there is no MIDI to fall back to.
  # Coverage is therefore a correctness property, not a nicety.
  musicPsf = fetchurl {
    url = "https://www.ff8.fr/download/programs/FFNx-FF8Music-v1.5.zip";
    hash = "sha256-E228AjwMIzDsrBH9yLaJTlSMVa+p/A8n7GfHA+SVM7Y=";
  };

  musicOstRf = fetchurl {
    name = "OST-RF.iroj";
    urls = [
      "https://modcdn.win/ost-rf/OST-RF.iroj"
      "https://download.tsunamods.com/?id=18"
    ];
    hash = "sha256-uqZwxpvjoeiz3uYHZhWnQ8WV1ipELVaxNjKUalQ6xF4=";
  };

  # Both modes install into a single music/ directory and set
  # external_music_path to it, so there is one lookup root and one bios
  # location regardless of mode.
  mkMusic =
    mode:
    runCommandLocal "ff8-music-${mode}"
      {
        nativeBuildInputs = [
          unzip
          python3
        ];
      }
      (
        ''
          mkdir -p "$out/music"
          unzip -q -o ${musicPsf} 'psf/*' -d "$TMPDIR"

          # The PSX rendering: minipsf sequences plus the SPU sample
          # library, played through FFNx's built-in OpenPSF. hebios.bin is
          # the Highly-Experimental BIOS that emulation needs -- without it
          # every track is silent, so it is not optional.
          cp "$TMPDIR/psf"/*.minipsf "$out/music/"
          cp "$TMPDIR/psf/FF8.psflib" "$TMPDIR/psf/hebios.bin" "$out/music/"
        ''
        + lib.optionalString (mode == "psx") ''
          cp "$TMPDIR/psf/config.toml" "$out/music/"
        ''
        + lib.optionalString (mode == "orchestral") ''
          python3 ${./iro-extract.py} ${musicOstRf} "$TMPDIR/ost"
          cp "$TMPDIR/ost/music"/*.ogg "$out/music/"

          # OST-RF's config.toml is a superset of the PSF one (same
          # no_intro_track/intro_seconds entries plus a joriku volume), so
          # it wins here rather than merging two files.
          cp "$TMPDIR/ost/music/config.toml" "$out/music/"

          # Two upstream naming bugs, both of which would play SILENCE
          # because these are sequenced tracks with no wav fallback.
          # Copy rather than rename so the pack stays as shipped:
          #   missle.ogg  -> FFNx asks for "missile" (068s-missile.sgt)
          #   eyesonme.ogg -> FFNx asks for "eyes_on_me" (music.cpp:45)
          for pair in "missle:missile" "eyesonme:eyes_on_me"; do
            src="$out/music/''${pair%%:*}.ogg"
            dst="$out/music/''${pair##*:}.ogg"
            if [ -f "$src" ] && [ ! -f "$dst" ]; then cp "$src" "$dst"; fi
          done
        ''
        + ''
          test -s "$out/music/hebios.bin"
          test -f "$out/music/config.toml"
          test "$(ls "$out/music" | wc -l)" -gt 90
        ''
      );

  # Voice acting. Tsunamods Echo-S 8, a human-cast recording of the field
  # dialogue -- the only voiced FF8 that exists. It is a DEMO and the full
  # release has never shipped: coverage runs from the game start to
  # entering Timber, at which point it forces a game over on purpose.
  #
  # FFNx's FF8 voice layer is complete (voice.cpp:1403-1450 patches the
  # field mes/ames/ask opcodes, battle name getters and 15 world-map
  # assign_text sites), so nothing here needs an engine change. Lookup is
  # <basedir>/voice/<field>/<dialog>[<page>].ogg, which is exactly how the
  # pack is laid out.
  #
  # Unlike every other mod here this one needs a three-way split rather
  # than the texture helper's "everything that is not mods/ is direct/":
  #   voice/  -> game root, where external_voice_path points
  #   FIELD/  -> direct/, engine file overrides (scripts and dialogue)
  #   movies/ -> Data/movies/, where FFNx asks for disc%02i_%02ih.avi
  # The movies are the voiced FMVs and are NOT optional: the pack's own
  # field scripts invoke disc00_31h/32h, movie slots vanilla does not have.
  voicePack = fetchurl {
    name = "echo-s-8-demo.iroj";
    urls = [
      "https://modcdn.win/uprisen/Echo-S%208%20Demo.iroj"
      "https://download.tsunamods.com/?id=20"
    ];
    hash = "sha256-WJQ9WerWa+OthyKcL6FeCmnT/LF0MhjXg3ODhqhqYdY=";
  };

  mkVoicePack =
    runCommandLocal "ff8-voice-echo-s-8-demo"
      {
        nativeBuildInputs = [ python3 ];
      }
      ''
        mkdir -p "$out"
        python3 ${./iro-extract.py} ${voicePack} "$TMPDIR/echos"

        cp -r "$TMPDIR/echos/voice" "$out/voice"

        mkdir -p "$out/direct"
        cp -r "$TMPDIR/echos/FIELD" "$out/direct/FIELD"

        mkdir -p "$out/Data"
        cp -r "$TMPDIR/echos/movies" "$out/Data/movies"

        # The archive carries a few working files that are inert with
        # external_voice_ext = "ogg" but have no business in a store path.
        find "$out/voice" -name '*.sfk' -delete
        find "$out/voice" -name '*.wav' -delete
        find "$out/voice" -name '* - Copy.ogg' -delete

        test "$(find "$out/voice" -name '*.ogg' | wc -l)" -gt 3000
        test -d "$out/direct/FIELD/mapdata"
        test -n "$(find "$out/Data/movies" -name '*.avi' -print -quit)"
      '';

  # FFNx is the engine layer this package is built around. It is the
  # modern graphics/audio driver for the classic FF8 engine, and it is
  # what makes the rebalance-mod ecosystem reachable: every gameplay mod
  # in circulation for this release is an FFNx mod (verified against
  # HobbitDur/HobbitInstaller's own compatibility switch, which maps
  # FF8_2000 + FF8_2013 -> FFNx and FF8_REMASTER -> Demaster, and whose
  # catalogue lists zero gameplay mods on the Demaster path).
  #
  # Install is a pure file drop next to FF8_EN.exe -- no injector, no
  # resident launcher, no registry. That is why this package targets
  # FFNx and NOT the older Roses-and-Wine / HextLaunch tooling that
  # every 2013-era mod README still tells you to install: RaW needs a
  # second always-running FF8+.exe doing cross-process DLL injection,
  # which is exactly the shape that behaves worst under gamescope.
  # FFNx supersedes it -- `hext_patching_path = "hext"` in FFNx.toml
  # applies the same Hext .txt patches those mods ship.
  #
  # Only the `FFNx-Steam` artifact is correct here. `FFNx-FF8_2000` is
  # for the Eidos CD release, and FFNx-FF8_Remastered exists ONLY on the
  # rolling `canary` tag (every stable release from 1.5.3 through 1.24.3
  # ships exactly FF7_1998 + FF8_2000 + Steam) and is documented as
  # incomplete: "You will most likely encounters crashes in battle".
  ffnx = fetchurl {
    url = "https://github.com/julianxhokaxhiu/FFNx/releases/download/canary/FFNx-Steam-v1.24.3.172.zip";
    hash = "sha256-OpoAvAGPVnQ3AlcQrN046zwiu2VmA6cP+zL1hfvu48o=";
  };

  # gbe_fork (Goldberg): an offline steam_api.dll, and the other half of
  # what makes FFNx usable here.
  #
  # This is a Steamworks title, so the engine's own SteamAPI_Init has to
  # succeed or it dies on "Steam must be running to play this game with
  # achievements". A GENUINE steam_api.dll cannot do that offline -- it
  # needs a live client -- so an emulator has to own that slot.
  #
  # Until 2026-07-26 that was impossible alongside FFNx, because stable
  # 1.24.3 shipped its own steam_api.dll into the same filename and
  # validated it (Authenticode signature, else SHA1
  # 03bd9f3e352553a0af41f5fe006f6249a168c243 -- the genuine Valve blob,
  # the same one Junction VIII whitelists), so an emulator there made FFNx
  # refuse to load. Commit b62ccf0b split the two names: FFNx now installs
  # the Valve DLL as FFNx_steam_api.dll, validates THAT, and explicitly
  # stops deploying steam_api.dll (CMakeLists.txt:346-349 and 654-656).
  # Verified against the artifact: the canary zip above contains
  # FFNx_steam_api.dll and no steam_api.dll at all.
  #
  # FFNx never actually calls Steam here either way -- its whole Steam
  # block is gated on `enable_steam_achievements` (common.cpp:828), shipped
  # false -- so the Valve DLL just sits there satisfying the check.
  #
  # Same release pin as games/antichamber, the repo's other 32-bit user.
  gbeFork = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };

  # The process proton actually tracks, and the reason the game is
  # playable at all.
  #
  # FF8_Launcher.exe does NOT exit when it starts the game, and while it
  # lives the game is unplayable: gamescope has to pick a primary window
  # out of nine (the launcher, its Notice, a Debug window, Steam, SteamVR
  # Status, Input, an IME window and the game) and the engine's keyboard
  # and mouse stay dead, including in its own control-config screen.
  # Junction VIII solves this the same way, enumerating FF8_Launcher
  # processes and killing them.
  #
  # The launcher cannot simply be killed from preRun, though: it is the
  # process `proton waitforexitandrun` is waiting on, so its death ends
  # the session and takes the game with it (measured -- the game died
  # four seconds after the kill). So the tracked process has to be
  # something that outlives it. This supervisor is built for the windows
  # subsystem, so it never creates a window of its own; it starts the
  # launcher, waits for the engine to appear, retires the launcher, and
  # then waits on the GAME so the session ends when the game does.
  #
  # Everything here is process lifecycle -- nothing is clicked and no UI
  # is automated. The operator still presses PLAY once. Skipping that
  # needs FF8_EN.exe to start directly, which is gated behind a launcher
  # handshake of four named semaphores (ff8_{launcher,game}{CanRead,
  # DidRead}MsgSem) plus at least one predicate that is still
  # unidentified; supplying all four is not sufficient, and argv, the
  # environment, the Steamworks emulator, named sections and the parent
  # process name have each been ruled out by measurement.
  launchSupervisor = pkgs.pkgsCross.mingw32.stdenv.mkDerivation {
    pname = "strom-ff8-supervisor";
    version = "1";
    dontUnpack = true;

    buildPhase = ''
      runHook preBuild
      cat > supervisor.c <<'CEOF'
      #include <windows.h>
      #include <tlhelp32.h>

      static DWORD find_pid(const char *exe)
      {
          PROCESSENTRY32 entry;
          DWORD pid = 0;
          HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

          if (snap == INVALID_HANDLE_VALUE)
              return 0;

          entry.dwSize = sizeof entry;
          if (Process32First(snap, &entry)) {
              do {
                  if (lstrcmpiA(entry.szExeFile, exe) == 0) {
                      pid = entry.th32ProcessID;
                      break;
                  }
              } while (Process32Next(snap, &entry));
          }

          CloseHandle(snap);
          return pid;
      }

      int WINAPI WinMain(HINSTANCE self, HINSTANCE prev, LPSTR args, int show)
      {
          STARTUPINFOA si;
          PROCESS_INFORMATION pi;
          char cmd[] = "FF8_Launcher.exe";
          DWORD game = 0;
          int i;

          (void)self; (void)prev; (void)args; (void)show;

          ZeroMemory(&si, sizeof si);
          si.cb = sizeof si;
          if (!CreateProcessA("FF8_Launcher.exe", cmd, NULL, NULL, FALSE, 0,
                              NULL, NULL, &si, &pi))
              return 2;

          /* Wait for PLAY. Bounded so a session that is never started
             still terminates instead of hanging forever. */
          for (i = 0; i < 3600 && game == 0; i++) {
              game = find_pid("FF8_EN.exe");
              if (game == 0)
                  Sleep(1000);
          }

          if (game != 0) {
              HANDLE handle;

              /* Let the engine finish taking over the display first. */
              Sleep(4000);
              TerminateProcess(pi.hProcess, 0);

              handle = OpenProcess(SYNCHRONIZE, FALSE, game);
              if (handle) {
                  WaitForSingleObject(handle, INFINITE);
                  CloseHandle(handle);
              }
          } else {
              WaitForSingleObject(pi.hProcess, INFINITE);
          }

          CloseHandle(pi.hThread);
          CloseHandle(pi.hProcess);
          return 0;
      }
      CEOF
      $CC -O2 -mwindows -o strom-ff8-supervisor.exe supervisor.c
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp strom-ff8-supervisor.exe "$out/"
      runHook postInstall
    '';
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  imports = [
    (
      { config, lib, ... }:
      let
        inherit (lib) mkOption types;
      in
      {
        options = {
          mods = mkOption {
            type = types.listOf types.package;
            default = [ ];
            description = ''
              Mod derivations stacked onto FF8 as additional overlay
              lowers, above `_gameData`. Nothing is installed by
              default: the base game is shipped mod-*ready* and each
              mod is opt-in, composed through
              `flake.modules.<arch>.final-fantasy-viii.apply { mods = [ ... ]; }`.

              A rebalance mod for this release is a plain file tree, so
              an entry should be shaped like the game root, i.e.

                Data/lang-en/{battle,field,main,menu}.{fi,fl,fs}

              replacing the stock archives. Hext text patches (the
              `*_mod.txt` files those mods ship, e.g.
              `Ragnarok_mod.txt`) go in `hext/` instead, which FFNx
              reads via `hext_patching_path`; that is the launcher-free
              replacement for the "install Roses and Wine, drop the txt
              in RaW/GLOBAL/Hext" step in the mods' own instructions.

              Stacking rather than baking keeps the 3.7 GB base tree out
              of every mod permutation -- toggling a mod does not
              re-extract the game. Later list entries win on conflicting
              paths.
            '';
          };

          internalResolutionScale = mkOption {
            type = types.ints.between 0 8;
            default = 2;
            description = ''
              FFNx supersampling factor, in multiples of 640x480. The
              engine renders at this size and FFNx downsamples to the
              window, so 2 means 1280x960 internally, 4 means 2560x1920.

              This is NOT cosmetic tuning, it is a defect fix. FFNx ships
              window_size_x/y = 0, which its own docs define as "window
              mode will use 640x480", and internal_resolution_scale = 0,
              which then auto-matches that. The result is a 480p game
              stretched to the gamescope output -- measured by capturing
              the live window, which came back exactly 640x480. The window
              size is now pinned to the gamescope nested resolution below,
              and this supersamples on top of it.

              0 restores FFNx's auto behaviour (match the window).
            '';
          };

          music = mkOption {
            type = types.enum [
              "vanilla"
              "psx"
              "orchestral"
            ];
            default = "vanilla";
            description = ''
              Replace the soundtrack. The 2013 release ships the 2000 PC
              port's audio verbatim: 91 DirectMusic .sgt sequences rendered
              through an 8 MB DLS instrument bank, i.e. a General-MIDI-class
              software synth. It is the largest fidelity gap in this package.

              "vanilla"    the DLS synth as shipped.
              "psx"        FFNx FF8Music v1.5 -- the actual PlayStation
                           soundtrack as minipsf, emulated through FFNx's
                           built-in OpenPSF. 14 MB, sample-accurate, and it
                           covers all 91 sequenced tracks.
              "orchestral" Tsunamods OST-RF v1.2 -- a from-scratch studio
                           reorchestration with live strings and guitars,
                           103 tracks, 709 MB of Vorbis. Someone else's
                           arrangement rather than FF8's music, so it is a
                           deliberate choice, not an upgrade. The PSX set is
                           layered underneath: FFNx walks
                           external_music_ext in order until a file exists
                           (audio.cpp:113-137), so the PSX rendering covers
                           the tracks OST-RF omits instead of leaving them
                           silent.

              Either non-vanilla mode keeps the game's own 16-bit PCM
              ambiences and Eyes on Me, which beat any lossy replacement --
              FFNx falls back to a .wav-backed track's original file, so
              only the sequenced half is swapped.
            '';
          };

          voices = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Install Tsunamods Echo-S 8, a human-cast voice acting mod --
              the only voiced FF8 that exists. FFNx's FF8 voice layer is
              complete, so this is a pure file drop.

              It is a DEMO and the full version has never been released.
              Read this before enabling:

              - Coverage runs from the game start to entering Timber. On
                arrival it forces a game over deliberately. Save before
                Timber, disable this, reload.
              - It rewrites dialogue: its .msd script files carry Echo-S's
                own script edits, not just audio.
              - Character and GF naming is locked to canon names so the
                recorded lines stay correct.
              - 1.2 GB: 618 MB of speech (~4.5 h across 108 field maps) plus
                633 MB of re-encoded FMVs. The FMVs are not optional -- its
                field scripts invoke disc00_31h/32h, movie slots vanilla
                does not have.
            '';
          };

          fieldBackgrounds = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Install 4x-upscaled field backgrounds -- the pre-rendered
              room and location art, which is what dominates the screen in
              any non-battle scene and which `textures` does not touch.

              AxlRose's WIP, the only free FFNx-native field pack that is
              still maintained. 157 of 877 maps, 564 MB extracted from a
              321 MiB download; Balamb Garden and Ifrit's Cave are
              complete, everything else is still vanilla, so expect a
              visibly inconsistent game. Opt-in for that reason.

              Composes with everything else here: it writes only
              mods/Textures/field/mapdata, which no texture pack touches
              and which is disjoint from ragnarok's direct-mode field
              scripts.
            '';
          };

          textures = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Install the Tsunamods HD texture packs -- all of them:

                Horizon Pack Plus v2.4        world map and town textures
                Poly-UP v4.5                  character models and textures
                Lunar Cry Plus v4.4           enemy textures
                BattlefieldPack Plus v2.2     battlefield textures
                ProjectHELLFIRE Plus v2.5     Guardian Force textures
                Rebirth Flame Plus v2.0       character textures
                Hit-J Plus v2.1               spell and effect textures
                Skin-RF v1.62                 battle model textures

              They are ESRGAN/Gigapixel upscales of the original art by
              MCINDUS and collaborators, and between them they cover
              essentially every surface the game draws. About 1.2 GB of
              downloads.

              Composes with `ragnarok`: these only add files under
              mods/Textures and direct/, and touch none of the four
              Data/lang-en archives a rebalance replaces. Requires `ffnx`
              (the default), which is what reads mods/Textures.
            '';
          };

          ragnarok = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Install the Ragnarok Rebalancing Mod v1.2.3 (Callisto).

              The most popular FF8 mod there is: 874 replies on its qhimm
              thread versus 139 for FFVIII Crystal and 112 for New Threat,
              and the only gameplay entry in HobbitInstaller's catalogue
              for this release.

              Installs BOTH halves. The `Data/lang-en` archives carry the
              rebalance itself (kernel.bin lives in main.fs -- stats,
              magic, GF abilities, enemies, items, draw points), and the
              Hext patch list covers what the data cannot express: ATB
              filling speed, the 255%-hit-rate removal, Protect/Shell
              damage reduction, the Vit-0 change.

              The Hext half needs `ffnx = true` (the default) since FFNx
              is what applies Hext; with `ffnx = false` the data half
              still works on its own and the patch file is simply unread.

              The author's own verification, if you want to confirm it
              in-game: Squall starts a new game with spells already
              junctionable (that is the data half), and the Draw Point in
              Balamb Garden's library holds Double instead of Esuna (that
              is the Hext half).
            '';
          };

          ragnarokMode = mkOption {
            type = types.enum [
              "standard"
              "lionheart"
            ];
            default = "standard";
            description = ''
              Which Ragnarok difficulty variant to install. Both ship in
              the same download and differ only in the six replaced
              `Data/lang-en` archives; "lionheart" is the harder one.
              Ignored unless `ragnarok` is set.
            '';
          };

          ffnx = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Install the FFNx driver over the stock Steam renderer. FFNx
              replaces the 2013 build's D3D path with its own (Vulkan
              here), and it is the layer every texture pack, the
              external-music mods and the Hext half of the gameplay mods
              are written against.

              This needs the CANARY build, not stable, and that is not a
              preference either. Until 2026-07-26 FFNx shipped its own
              steam_api.dll into the same filename the game imports and
              validated it (Authenticode signature, else SHA1
              03bd9f3e352553a0af41f5fe006f6249a168c243, the genuine Valve
              blob that Junction VIII also whitelists), so the emulator
              this tree needs in that slot made FFNx refuse to load.
              Commit b62ccf0b split the names: FFNx installs the Valve DLL
              as FFNx_steam_api.dll, validates THAT, and explicitly stops
              deploying steam_api.dll (CMakeLists.txt:346-349, 654-656).
              Stable 1.24.3 predates it by four months.

              It also needs the `__CFBundleIdentifier` env var below.

              PIN HAZARD: `canary` is a rolling tag whose assets are
              replaced in place, so the fetchurl hash WILL stop matching
              when upstream rebuilds. That fails the build loudly rather
              than silently, and the fix is to re-pin; switch to a stable
              release once one ships with b62ccf0b in it.
            '';
          };

        };

        config = {
          name = "final-fantasy-viii";

          # Final Fantasy VIII, 2013 Square Enix PC re-release (Steam
          # appid 39150), run under Proton with FFNx.
          #
          # WHY THIS RELEASE, of the three that exist:
          #   * 2000 Eidos CD release -- four CDs, General MIDI music
          #     instead of the PSX soundtrack, and no rebalance mod
          #     names it as a supported target. FFNx additionally pops a
          #     MessageBox for Eidos-patch executables ("not supported
          #     and has not been tested").
          #   * 2019 Remastered -- a different product with its own
          #     Lutris slug (final-fantasy-viii-remastered). Its mod
          #     path needs Demaster, and the flagship rebalance mod
          #     (Callisto's Ragnarok) lists 14 features at 0% there
          #     versus 100% on 2013 -- including the ATB filling-speed
          #     fix, whose absence its author says makes the max battle
          #     speed setting unplayable. Its install additionally
          #     requires hand-patching FFVIII_EFIGS.dll with an IPS
          #     patch through an external web tool, which cannot be
          #     automated in a derivation.
          #   * 2013 Steam -- 11+ exclusive rebalance mods, the two
          #     best-maintained overhauls at full feature parity, and a
          #     file-drop install. This one.
          #
          # The PlayStation release is a *fourth* option and was what
          # this slug used to hold (RetroArch + SwanStation, four .chd
          # discs). It emulates cleanly but cannot take PC mods at all,
          # which is the whole point of this package, so it was dropped
          # rather than shipped alongside -- Lutris has exactly two FF8
          # entries and the 2013 release *is* `final-fantasy-viii`
          # (entry 1670, whose Steam provider is appid 39150), so
          # shipping both would have required inventing a slug.
          #
          # PROVENANCE, stated plainly because it is not the
          # publisher's bytes. The source is the archive.org item
          # `CA-WINDOWS-Final-Fantasy-8`: a complete already-installed
          # 2013 tree, 477 files, loose (no installer to run). The game
          # DATA is stock -- every file dated 2013-03-03, and the
          # lang-en archive sizes cross-check against what the mods
          # expect to replace (battle.fs 55,456,819 -> mod 55,463,580;
          # field.fs 294,122,967 -> 294,150,051; main.fs 4,668,301 ->
          # 4,669,333). The EXECUTABLE is not stock: SHA1
          # 65A7994729E9F8D720983B0BD5FD3F8D3FED5287 matches none of the
          # three known-good hashes, and its PE section table carries an
          # appended `.inlaws` section (VA 0x02428000, 0x115 bytes)
          # beside the stock `.dotemu`/`.weare` sections, plus
          # `steam_inlaws32.ini` and `unins000.exe` in the tree.
          #
          # That tampering was measured against FFNx's own detector
          # rather than assumed fatal. FFNx reads two dwords from the
          # loaded image (src/common.cpp, get_version(): VA 0x401004 and
          # 0x401404) and matches a table. Read straight out of this
          # PE they are 0x3885048D and 0x1597C8 -- an exact match for
          # the documented "FF8 1.2 US English (Nvidia)" pair, a fully
          # supported version and NOT the Eidos pair that warns. `.text`
          # is also intact in position and size (VA 0x1000, 0x768000
          # bytes), with the crack confined to its own appended section,
          # which is what Hext byte-patching depends on.
          #
          # If a pristine tree is ever wanted, appid 39150 is still sold
          # and `steamcmd +app_update 39150 validate` produces publisher
          # bytes satisfying every hash above; only the two cid/hash
          # pairs below would change.
          src = fetchIpfs {
            cid = "QmWB3qGAdcU2Uu9Q55dXq82HxgCUDUNizDVJfghvTwckg4";
            fallbackUrl = "https://archive.org/download/CA-WINDOWS-Final-Fantasy-8/Final%20Fantasy%208.7z";
            hash = "sha256-454gxyReyO0DcNssARSC7lcuERAA+sh0rvg71UuP6Cw=";
            name = "final-fantasy-viii-2013-steam.7z";
          };

          ipfsSources = [ config.src ];

          nativeBuildInputs = [
            p7zip
            unzip
            binutils
          ];

          buildScript = ''
            mkdir -p "$out"

            # The archive wraps everything in a single "Final Fantasy 8"
            # directory; the game root has to be $out itself, so that
            # `executable` and any driver file drop land beside each
            # other.
            7z x -bso0 -bsp0 -o"$TMPDIR/game" "$src"
            mv "$TMPDIR/game/Final Fantasy 8"/* "$out"/
            chmod -R u+w "$out"

            # The 2013 executable reads its appid from here when no
            # client is present.
            echo -n 39150 > "$out/steam_appid.txt"

            # The Inno uninstaller is dead weight -- nothing loads it and
            # it only invites confusion about what runs. Everything else
            # in the tree STAYS, including steam_inlaws32.ini and
            # iNLAWS/: the executable's ownership bypass reads both, and
            # deleting them makes it exit before rendering a frame
            # (measured).
            rm -f "$out/unins000.exe" "$out/unins000.dat"

            # The windowless supervisor that proton tracks (see above).
            install -m0755 ${launchSupervisor}/strom-ff8-supervisor.exe "$out/"
          ''
          + lib.optionalString config.ffnx ''

            # Drop FFNx over the stock Steam renderer -- AF3DN.P/AF4DN.P
            # are the game's own driver stubs and FFNx replaces them in
            # place. `-o` overwrites without prompting, which
            # deliberately includes steam_api.dll: FFNx validates that
            # the one beside the executable is its own, so it must win.
            #
            # This is gated behind `ffnx` because it is incompatible with
            # THIS tree's cracked executable (see the option's
            # description). Enable it together with a legitimate tree.
            unzip -q -o ${ffnx} -d "$out"

            # Give FFNx a real resolution. Its shipped defaults render
            # 640x480 in window mode (FFNx.toml "[RESOLUTION]"), which
            # gamescope then stretches; pin the window to the same size
            # gamescope nests at so the two cannot disagree, and
            # supersample per internalResolutionScale.
            substituteInPlace "$out/FFNx.toml" \
              --replace-fail 'window_size_x = 0' 'window_size_x = ${toString config.gamescope.nested-width}' \
              --replace-fail 'window_size_y = 0' 'window_size_y = ${toString config.gamescope.nested-height}' \
              --replace-fail 'internal_resolution_scale = 0' 'internal_resolution_scale = ${toString config.internalResolutionScale}'

            ${lib.optionalString (config.music != "vanilla") ''
              # Point FFNx at the music/ tree the mkMusic lower provides.
              # None of this is defaulted for the Steam 2013 edition: FFNx
              # force-enables external music only for FF7 Steam and FF8
              # Remastered (common.cpp:3220,3323), and its unconditional
              # external_music_path fallback (common.cpp:3373) is
              # data/music/dmusic/ogg -- a directory this build does not
              # have. Unset, the game simply goes silent, because FFNx has
              # already replaced play_midi by then (music.cpp:1213).
              #
              # ff8_external_music_force_original_filenames stays false: it
              # exists to feed Remastered oggs in under their raw .sgt
              # names, and both packs here use FFNx's truncated naming
              # (005s-battle.sgt -> battle, music.cpp:148-160).
              substituteInPlace "$out/FFNx.toml" \
                --replace-fail 'use_external_music = false' 'use_external_music = true' \
                --replace-fail 'external_music_path = ""' 'external_music_path = "music"' \
                --replace-fail 'he_bios_path = ""' 'he_bios_path = "music/hebios.bin"' \
                --replace-fail 'external_music_ext = "ogg"' ${
                  if config.music == "orchestral" then
                    "'external_music_ext = [ \"ogg\", \"minipsf\" ]'"
                  else
                    "'external_music_ext = \"minipsf\"'"
                }
            ''}
            ${lib.optionalString (config.music == "orchestral") ''
              # OST-RF's own README asks for both of these; sync keeps the
              # arranged tracks aligned with the engine's loop points.
              substituteInPlace "$out/FFNx.toml" \
                --replace-fail 'external_music_volume = -1' 'external_music_volume = 75' \
                --replace-fail 'external_music_sync = false' 'external_music_sync = true'
            ''}

            # FFNx must find the Valve DLL it validates. It ships no
            # steam_api.dll of its own (verified against the artifact), so
            # the tree's own emulator keeps that slot -- which is what the
            # cracked executable is bound to. A generic emulator does NOT
            # substitute: gbe_fork in that slot loads and FFNx is happy,
            # but the engine's SteamAPI_Init still fails ("Steam not
            # running error"), because the crack talks to the emulator it
            # shipped with.
            test -s "$out/FFNx_steam_api.dll"
            test -s "$out/steam_api.dll"
          '';

          runtime = "proton";
          # The supervisor, which starts FF8_Launcher.exe and retires it
          # once the engine is up (see launchSupervisor above). It must be
          # the tracked process: proton waits on whatever it launches, so
          # with the launcher tracked directly, reaping it ends the
          # session and kills the game.
          executable = "strom-ff8-supervisor.exe";

          # Verified from Junction VIII's own source (which reads and
          # writes these paths for its save/controller handling):
          # GameConverter.GetSteamFF8UserPath() is
          # `Documents\Square Enix\FINAL FANTASY VIII Steam`, holding
          # `user_<steamid>/` subdirectories with the `*.ff8` saves, plus
          # `ff8input.cfg` alongside them. All of it lives under the
          # wineprefix, which the launcher treats as disposable, so the
          # whole directory is relocated into ~/.strom/<name>/.
          saveLocations = [ "Documents/Square Enix/FINAL FANTASY VIII Steam" ];

          # The game creates its userdata directory only when a Steam
          # client hands it a user id, which never happens here, and the
          # engine treats the absence as fatal: on a fresh prefix it
          # exits before rendering, and FFNx (which autodetects this
          # directory by globbing `user_*`) has nothing to find. Seeding
          # one empty `user_1` is the whole fix -- measured: without it
          # the process is gone within seconds, with it the engine stays
          # up and gets as far as its own Steam check.
          #
          # This writes to $STROM_GAMEDIR rather than into the prefix
          # because `saveLocations` above relocates the directory there
          # and symlinks it back, so seeding the persistent side is
          # correct on a wiped prefix AND on first launch, when proton
          # has not created the prefix yet at preRun time.
          preRun = ''
            mkdir -p "$STROM_GAMEDIR/FINAL FANTASY VIII Steam/user_1"
          '';

          # Materialize the driver files into the writable upper. Wine's
          # loader only reliably prefers an app-local native module over
          # a builtin when the file is physically present there (same
          # reason games/stalker-anomaly lists its d3dx9 DLLs), and FFNx
          # rewrites FFNx.log beside them. FFNx.toml and hext/ are listed
          # because they are the user-facing knobs: a mod's Hext patch is
          # dropped into hext/.
          copyGlobs = [
            "AF3DN.P"
            "AF4DN.P"
          ]
          ++ lib.optionals config.ffnx [
            "FFNx.toml"
            "hext"
          ];

          # Stack opt-in mods above the base tree. mkBefore prepends to
          # mk-game's default `[ _gameData ]`, so mod files win on path
          # conflict and the base game is never re-extracted.
          bwrap.overlay.lowers = lib.mkBefore (
            map toString (
              config.mods
              ++ lib.optional config.ragnarok (mkRagnarok config.ragnarokMode)
              ++ lib.optionals config.textures texturePackLowers
              ++ lib.optional config.fieldBackgrounds (mkTexturePack "fields" fieldBackgroundPack)
              ++ lib.optional (config.music != "vanilla") (mkMusic config.music)
              ++ lib.optional config.voices mkVoicePack
            )
          );

          # FFNx force-enables Steam achievements for the Steam edition,
          # overriding the `enable_steam_achievements = false` it ships:
          # common.cpp:3338 does `enable_steam_achievements = !macOsLauncher`
          # the moment it detects af3dn.p. It then calls SteamAPI_Init
          # unconditionally (common.cpp:845) and dies on "Steam must be
          # running to play this game with achievements" -- there is no
          # live Steam client here and never will be.
          #
          # `macOsLauncher` is decided entirely by an environment variable
          # (utils.cpp:169-174: __CFBundleIdentifier ==
          # "com.julianxhokaxhiu.SummonKit", the author's own macOS
          # wrapper), so setting it takes the whole Steam path out of play
          # and FFNx renders happily offline. Verified: the game window
          # becomes "Final Fantasy VIII (Vulkan) 1.24.3.172" and the
          # opening FMV plays, with no Steam dialog.
          env = lib.mkIf config.ffnx {
            __CFBundleIdentifier = "com.julianxhokaxhiu.SummonKit";
          };

          gamescope = {
            output-width = 1920;
            output-height = 1080;
            nested-width = 1920;
            nested-height = 1080;
          };
        };
      }
    )
  ];

  meta = {
    description = "Final Fantasy VIII (2013 Square Enix PC re-release, via Proton, mod-ready)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "final-fantasy-viii";
  };
}
