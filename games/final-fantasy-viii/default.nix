{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Every tree this game is made of, pinned once and fetched as-is by the
  # desktop (overlay lowers) and the Android client (unpacked layers)
  # from the same CIDs. Nothing is extracted or patched at build time any
  # more; the trees were produced once from the upstream archives and
  # pinned, and this file only names them. `hash` is `nix hash path` of
  # the tree, `size` its uncompressed bytes.
  tree =
    name: args:
    fetchIpfs (
      {
        inherit name;
        directory = true;
      }
      // args
    );

  # Ragnarok Rebalancing Mod v1.2.3 (Callisto), the 2013-Steam build:
  # the most popular FF8 mod by a wide margin, playtested start to
  # finish by its author. Two difficulty variants ship in one download
  # and differ only in six Data/lang-en files, so they are a
  # `ragnarokMode` choice rather than two packages. Each variant tree
  # holds the four replaced archives (battle, field, main, menu as
  # .fi/.fl/.fs) and the mod's Hext patch list under hext/ff8/en_nv/,
  # which is where FFNx looks for a Steam-2013 executable (its version
  # table reports this build as FF8 1.2 US NV). Hext patches apply to the
  # running process only, so a misplaced one no-ops rather than damaging
  # anything. The Hext half needs FFNx; without it only the data half
  # applies.
  ragnarok = {
    standard = tree "ff8-ragnarok-1.2.3-standard" {
      cid = "bafybeicbnm5ekth6orauv5bgtq7dqatqx6fewcuizonmjynrb5zhz5qnd4";
      hash = "sha256-Xvyhe6Q81tn+YlgF0CoD8LjHsCa/e3Z9+5KNAwTRiG4=";
      size = 356969624;
    };
    lionheart = tree "ff8-ragnarok-1.2.3-lionheart" {
      cid = "bafybeib4aftmigdo7u6u3fbthuu5tj2cj6bj63hbirbj5r2mpx5xdui76u";
      hash = "sha256-/E2498ol5yXF+CakGSf4UWyxiHf5wkEqFcKyX33qegQ=";
      size = 356970255;
    };
  };

  # Texture packs from the Tsunamods catalogue (gp-mc.net), where the FF8
  # graphics scene lives. Unpacked from their .iroj containers into
  # mods/Textures/ (FFNx's mod_path) plus direct/ for loose engine-file
  # overrides. They are texture replacements only -- none touches the
  # Data/lang-en archives -- so they compose freely with each other and
  # with `ragnarok`.
  #
  # Priority order, highest first, because they DO overlap: 118 of the
  # 1392 files collide, essentially all of them battle character textures
  # shipped by both Poly-UP (models AND textures, v4.5) and the older
  # Rebirth Flame Plus (textures only, v2.0). Overlay lowers are
  # first-wins, so Poly-UP goes first; the remaining packs cover disjoint
  # surfaces and their order is immaterial.
  texturePacks = [
    # Poly-UP v4.5 -- character models and textures
    (tree "ff8-texturepack-models" {
      cid = "bafybeianjl4vmppf67satqjyxnwc7imi57hq6hcf7v4hb5yyg2hekp72eq";
      hash = "sha256-iSko6Bzypp17WbtfmCOFAth2bxonAYRQwZNAD/htXfs=";
      size = 159665748;
    })
    # Rebirth Flame Plus v2.0 -- character textures
    (tree "ff8-texturepack-characters" {
      cid = "bafybeih7ztzudw6yx27rkbvznnuh75fkxboselkv4iujx3i3rtcxyzmrbq";
      hash = "sha256-P1WN6Nm1Xkk6Mc7nXalQ5nNb74kC1XrRBLNKEpcako0=";
      size = 155402980;
    })
    # Battle models
    (tree "ff8-texturepack-battleModels" {
      cid = "bafybeibwp3uhwbfno5qcku6qdmib4a67iptriz2oa5lkpuddnw5jcqsk3i";
      hash = "sha256-VOz/8iEUFKstZ5nMKRM78yII+s01SlGW0MSgYNcTsM8=";
      size = 161712636;
    })
    # ProjectHELLFIRE Plus v2.5 -- Guardian Force textures
    (tree "ff8-texturepack-gfs" {
      cid = "bafybeibxciicg5hldcwercfgkp66sdpourc3tggfx7bgsroxfdtpm5v25e";
      hash = "sha256-TiUcAttKg4Kt19fghiLPgufIH9v1kYjkhHgvrdOAC3o=";
      size = 282919830;
    })
    # Spell effects
    (tree "ff8-texturepack-spells" {
      cid = "bafybeifiz6fhobjrhjvhovljmnay3ny6f2y4ifgo7xy6w4tvkk6zuwcgla";
      hash = "sha256-kxeFp8TsX1x3XAGhHGZtRRgJ768wvjghENsAK+mrH8w=";
      size = 515801894;
    })
    # Lunar Cry Plus v4.4 -- enemy textures
    (tree "ff8-texturepack-enemies" {
      cid = "bafybeidvaiodhfzkjqnua4q55jninvoleb3zjjznckiu2fyqdcktppzg64";
      hash = "sha256-2umaoPppkFjMIRbKvZA8mXYMfbtkmIX5tbmhGzPurOA=";
      size = 25169376;
    })
    # BattlefieldPack Plus v2.2 -- battlefield textures
    (tree "ff8-texturepack-battles" {
      cid = "bafybeidjkah2k7nx4nz7jbfaxdwcm5wtmt4m6ojkwp5ew4zfzgjc6frbvy";
      hash = "sha256-v/BWmFTNRmGiYLH2BWfFD1ua2knuIqv6ueGXoXBOmKE=";
      size = 765376432;
    })
    # Horizon Pack Plus v2.4 -- world map and town textures
    (tree "ff8-texturepack-world" {
      cid = "bafybeiewayqskwrrnhfsyn4rvtlpu2pfzr4vhmmspdayhvbbo2abxwygni";
      hash = "sha256-LEAqI9ulra5flv0I/n8Si1WrlPhJJi8bcji46EOO2fY=";
      size = 52049856;
    })
  ];

  # AxlRose's WIP v2026.0705 -- 4x field backgrounds, 157 of 877 maps
  # (the _FBG_4XSHARP folder only; the rest of that archive is UI work
  # its own mod.xml cannot gate).
  fieldBackgrounds = tree "ff8-texturepack-fields" {
    cid = "bafybeibcu3qjq34sp6ogsz5s2qyxzik63unjapxdesdlbhuonod3s66gsi";
    hash = "sha256-cEIEGyb6DCk55p4YKzh3QUYp3OEix1vUfiMKhN/q1KU=";
    size = 590699204;
  };

  # Music. The 2013 release is the 2000 PC port's audio verbatim: 91
  # DirectMusic .sgt sequences rendered through an 8 MB DLS instrument
  # bank, a General-MIDI-class software synth and the biggest fidelity gap
  # left in this package. Each pack installs into music/ and carries the
  # FFNx.toml that points FFNx at it (external music is not defaulted for
  # the Steam 2013 edition, and with use_external_music on FFNx replaces
  # play_midi outright, so an unpointed pack plays SILENCE). The 19
  # Data/Music/stream/*.wav ambiences stay: FFNx falls back to the
  # original file for those.
  #
  #   psx         the PlayStation rendering: minipsf sequences plus the
  #               SPU sample library (FFNx-FF8Music v1.5, ff8.fr), played
  #               through FFNx's built-in OpenPSF with the hebios.bin it
  #               needs.
  #   orchestral  OST-RF (Tsunamods): arranged oggs, over the psx set as
  #               fallback, with FFNx's volume/sync settings the pack's
  #               README asks for, and two tracks duplicated under the
  #               names FFNx asks for (missile, eyes_on_me) because the
  #               pack misnames them.
  music = {
    psx = tree "ff8-music-psx" {
      cid = "bafybeibpvjr344pzyacsfqfxwr3urdm3vv4f7kdai3b7flqmtlu4v5fyb4";
      hash = "sha256-GU+mHM8rx5YKAUnHT1DKRZBcOQe4ScR0oCyViN9skWE=";
      size = 15319910;
    };
    orchestral = tree "ff8-music-orchestral" {
      cid = "bafybeifj2tjtsllgh6gllqt7eyftwvh5mkelolrrovhhd24qc26kxqq2ra";
      hash = "sha256-KVuGguwGKQ36GObPSzvFRnAkemk9TnzxZGfLPgjRY8I=";
      size = 779051544;
    };
  };

  # Voice acting. Tsunamods Echo-S 8, a human-cast recording of the field
  # dialogue -- the only voiced FF8 that exists. It is a DEMO and the full
  # release has never shipped: coverage runs from the game start to
  # entering Timber, at which point it forces a game over on purpose.
  # Laid out as FFNx reads it: voice/ at the game root, the pack's field
  # scripts under direct/FIELD/, and its voiced FMVs under Data/movies/
  # (not optional: the scripts invoke movie slots vanilla does not have).
  voices = tree "ff8-voice-echo-s-8-demo" {
    cid = "bafybeidqe2vvhl5izotkeiuhu7v775n57n3b6e5y756qfxwz34mxv65hca";
    hash = "sha256-ngXQHt0ff3FjGzSVPyImO4Zj6i4iXg7gDna8NeUK0sw=";
    size = 1312611023;
  };

  # FFNx, the modern graphics/audio driver for the classic FF8 engine and
  # what makes the mod ecosystem reachable: every gameplay mod for this
  # release is an FFNx mod. Install is a file drop next to FF8_EN.exe --
  # AF3DN.P/AF4DN.P are the game's own driver stubs and FFNx replaces
  # them; FFNx_steam_api.dll is the Valve DLL it validates, while the
  # tree's own steam_api.dll keeps its slot (the cracked executable is
  # bound to that emulator; a generic one makes SteamAPI_Init fail).
  #
  # This is the FFNx-Steam canary build v1.24.3.272 (a stable release
  # cannot replace it: the b62ccf0b steam_api split it depends on exists
  # only on canary) with ONE call NOP'd out: ffnx_log_current_pc_specs()
  # at 0x3ACB3A of AF3DN.P, whose locale setup aborts the 32-bit ucrtbase
  # of proton-arm64ec on every launch (traced with +relay on the AYN
  # Thor). The desktop's x86_64 ucrtbase survives it, which is why it
  # never showed on Linux. Plus FFNx.toml with the backend pinned to
  # Direct3D 11 (the one bgfx backend measured to survive everywhere; on
  # the Thor auto chose OpenGL and died at 1920x1080), fullscreen at the
  # size gamescope nests at, and internal_resolution_scale = 2: FFNx's
  # shipped zeros mean 640x480 stretched to the output (measured by
  # capturing the live window), so the window is pinned and the engine
  # supersamples at 1280x960 on top of it. A music pack's own FFNx.toml
  # sits above this one. FFNx.pdb (148 MB of debug symbols) is left out.
  ffnx = tree "ff8-ffnx-1.24.3" {
    cid = "bafybeifxwghrrqbvbepdspitqji5ty5rk3ipdmvkw52slqgjunlycpj3t4";
    hash = "sha256-vTQ2d+iT+tKVWWfJuYTPs5+ycT8xQsi/kSwvOCYfTvU=";
    size = 41011267;
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
              lowers, above the base tree. Nothing is installed by
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

              The layer is a pinned tree of the canary build (see `ffnx`
              above), so upstream replacing canary's assets in place, as
              it does on every CI build, changes nothing here.
            '';
          };

          # NOTE: every bool/enum option above reaches the couch launcher's
          # options screen automatically (lib/mk-game.nix builds the schema from
          # the recipe's own declarations), `ffnx` included. `mods` does not:
          # a list of derivations is not something a pad can present.
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
          # The base tree: the 2013 game files as the archive.org item
          # `CA-WINDOWS-Final-Fantasy-8` ships them (477 files, loose),
          # plus steam_appid.txt (the 2013 executable reads its appid
          # from there when no client is present) and the supervisor
          # below, minus the Inno uninstaller. Everything else STAYS,
          # including steam_inlaws32.ini and iNLAWS/: the executable's
          # ownership bypass reads both, and deleting them makes it exit
          # before rendering a frame (measured). No FFNx in here: that is
          # a layer like every other toggle.
          src = tree "final-fantasy-viii" {
            cid = "bafybeianarj35r6z2trxvjdd4nra22akasrudnm5eezhlflmtv6z6nfcni";
            hash = "sha256-p/+x1otZpuamAazwYqqqWNwCES9X9wJqirtD7zOtkPY=";
            size = 3698304904;
          };

          runtime = "proton";
          # strom-ff8-supervisor.exe, in the base tree, is the process proton
          # tracks and the reason the game is playable at all.
          # FF8_Launcher.exe does NOT exit when it starts the game, and while
          # it lives the game is unplayable: gamescope has to pick a primary
          # window out of nine and the engine's input stays dead. It cannot
          # simply be killed either: it is the process `proton
          # waitforexitandrun` waits on, so its death ends the session and
          # takes the game with it (measured). The supervisor is built for
          # the windows subsystem, so it never creates a window; it starts
          # the launcher, waits for the engine to appear, retires the
          # launcher, then waits on the GAME so the session ends when the
          # game does. Nothing is clicked. Source: ./supervisor.c, built
          # with `i686-w64-mingw32-gcc -O2 -mwindows`. Starting FF8_EN.exe
          # directly is gated behind a launcher handshake of four named
          # semaphores plus at least one unidentified predicate; argv,
          # environment, the Steamworks emulator, named sections and the
          # parent process name were each ruled out by measurement.
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

          # FF8_EN.exe imports dinput.dll (DirectInput 7) and sees no pad
          # under GameNative, whose pad support is XInput-shaped; keys do
          # arrive. These are the game's own defaults as its in-game
          # Keyboard screen lists them (ff8input.cfg files them under
          # shifted labels): Select=X, Cancel=C, Menu=V, Card game=S,
          # Rotation left/right=H/G, Switch POV=F, Toggle display=J,
          # Pause=A, Escape battle=D+F. Measured on an AYN Thor.
          android.padKeys = {
            a = "X";
            b = "C";
            y = "V";
            x = "S";
            l1 = "H";
            r1 = "G";
            l2 = "F";
            r2 = "J";
            start = "A";
            select = "D";
            dpad = "arrows";
            leftStick = "arrows";
          };

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

          # Every opt-in mod, declared once. mk-game mounts the ones the
          # current options select as overlay lowers and Android publishes
          # all of them as fetchable layers, so what a phone offers and what
          # the desktop mounts are the same list by construction.
          #
          # Highest priority first, matching `lowers`: Ragnarok's rebalance
          # over the texture packs, those over the field backgrounds, then
          # music and voices, and FFNx itself last, so that a music pack's
          # FFNx.toml wins over the driver's own.
          #
          # `mods` stays outside this: it is an operator escape hatch
          # holding arbitrary derivations, not a player-facing choice, so it
          # goes straight onto `lowers`.
          modLayers =
            map
              (mode: {
                key = "ragnarokMode";
                value = mode;
                # `ragnarokMode` picks the variant, `ragnarok` is the switch
                # that makes the pick mean anything; the enum's default
                # would otherwise select the rebalance for someone who
                # never asked for it.
                requires = {
                  key = "ragnarok";
                  value = "true";
                };
                tree = ragnarok.${mode};
              })
              [
                "standard"
                "lionheart"
              ]
            ++ map (tree: {
              key = "textures";
              value = "true";
              inherit tree;
            }) texturePacks
            ++ [
              {
                key = "fieldBackgrounds";
                value = "true";
                tree = fieldBackgrounds;
              }
            ]
            ++
              map
                (mode: {
                  key = "music";
                  value = mode;
                  tree = music.${mode};
                })
                [
                  "psx"
                  "orchestral"
                ]
            ++ [
              {
                key = "voices";
                value = "true";
                tree = voices;
              }
              {
                key = "ffnx";
                value = "true";
                tree = ffnx;
              }
            ];

          # The operator escape hatch, above the base game.
          bwrap.overlay.lowers = lib.mkBefore (map toString config.mods);

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
