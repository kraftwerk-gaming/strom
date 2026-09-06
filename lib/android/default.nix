# lib/android/default.nix
#
# Android sub-module of mkGame. Sits alongside `proton`, `bwrap`,
# `gamescope`, etc. The parent mk-game config is passed in via the
# `game` specialArg so this module can read game.name / game.runtime /
# game.executable directly without duplicating options.
#
# This is a plain submodule (not a wrapper module from wrappers.lib):
# nothing here is a shell wrapper around an exe and the wrapper
# schema's `package`/`exePath`/etc. have no meaning.
#
# Three outputs, three different jobs:
#
#   outputs.manifest  the per-game descriptor a Strom Android client
#                     reads to know WHICH runtime app to hand the game
#                     to, WHAT to fetch, and HOW to launch it. Pure
#                     projection of the game's default.nix; see
#                     docs/android.md for the schema and the rationale.
#
#   outputs.payload   the artifact that manifest points at: the game's
#                     built data tree (the same `_gameData` the desktop
#                     overlay lowers). Built and IPFS-pinned by the
#                     operator, then wired back in as `android.payload`
#                     so the manifest carries a real CID. Android cannot
#                     run a game's `buildScript` (arbitrary nix/bash
#                     calling innoextract, 7zz, patchelf, winetricks...),
#                     so the BUILT tree is what ships, not the source
#                     archive.
#
#   outputs.apk       per-game APK seam, for the rare game with a real
#                     self-contained Android build (e.g. a LOVE2D game via
#                     balatromobile -- see games/balatro/apk.nix). No
#                     default: this is NOT how the catalog reaches
#                     Android. A generic Wine/FEX APK pipeline was tried
#                     on the wip/android branch (43 commits) and bottoms
#                     out on wine-on-Android GPU work; the decision
#                     record is docs/android.md.

{
  lib,
  game,
  # The parent's resolved bool/enum option schema (mk-game's
  # `settingsSchema`, published as `passthru.settingsSchema`). Passed in
  # rather than recomputed: the manifest's options screen and the couch
  # launcher's must be the same list, not two implementations of one
  # rule.
  settingsSchema,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types;

  # Android package names disallow hyphens; the appId stem is the slug
  # with `-` stripped ("balatro" stays "balatro",
  # "need-for-speed-underground-2" -> "needforspeedunderground2").
  slugToAppId = slug: lib.replaceStrings [ "-" ] [ "" ] slug;

  # Which Android runtime app a desktop `runtime` hands off to. The
  # unsupported reasons are load-bearing: the client shows them instead
  # of a Play button, so they must say why, not just "no".
  backendFor = {
    proton = "gamenative";
    retroarch = "retroarch";
    dolphin = "dolphin";
    azahar = "azahar";
    pcsx2 = "unsupported";
    native = "unsupported";
    custom = "unsupported";
  };

  unsupportedReasons = {
    pcsx2 = "no redistributable source-available Android PS2 emulator exists (PCSX2 has no Android target; AetherSX2 is discontinued and closed; NetherSX2 is an unlicensed patch)";
    native = "a Linux x86_64 ELF needs box64 plus a glibc rootfs, and no Android runtime app exposes a way to launch one";
    custom = "custom runtimes are per-game shell scripts with no Android equivalent; port individually";
  };

  # libretro core .so as it lands in RetroArch Android's cores dir.
  # Derived from the nixpkgs libretro package's pname
  # ("libretro-melonds" -> "melonds_libretro_android.so"), with a table
  # for the cores whose Android build is named differently.
  androidCoreOverrides = {
    # buildbot.libretro.com/nightly/android/latest/arm64-v8a/ ships no
    # plain mupen64plus_next; only the gles2 and gles3 variants.
    "libretro-mupen64plus-next" = "mupen64plus_next_gles3_libretro_android.so";
  };

  coreFromPname =
    pname:
    androidCoreOverrides.${pname} or (
      let
        stem = lib.removePrefix "libretro-" pname;
      in
      if stem == pname then
        throw "android: cannot derive an Android core name from libretro package pname '${pname}'; set android.retroarchCore explicitly"
      else
        "${lib.replaceStrings [ "-" ] [ "_" ] stem}_libretro_android.so"
    );

  derivedCore =
    let
      cores = game.retroarch.cores;
    in
    if lib.length cores == 1 then
      coreFromPname (lib.head cores).pname
    else
      throw "android: ${game.name} has ${toString (lib.length cores)} retroarch cores; set android.retroarchCore explicitly";
in
{
  options = {
    appId = mkOption {
      type = types.str;
      default = "gaming.kraftwerk.strom.${slugToAppId game.name}";
      defaultText = lib.literalMD "`gaming.kraftwerk.strom.<game.name stripped of hyphens>`";
      description = "Android application id for the game's APK.";
    };

    versionName = mkOption {
      type = types.str;
      default = "0.1.0";
      description = "Android versionName stamped into the APK manifest.";
    };

    backend = mkOption {
      type = types.enum [
        "gamenative"
        "retroarch"
        "dolphin"
        "azahar"
        "apk"
        "unsupported"
      ];
      default = backendFor.${game.runtime};
      defaultText = lib.literalMD "derived from `runtime`";
      description = ''
        The Android runtime app this game is handed off to. `apk` means
        the game ships its own Android build via `outputs.apk` and needs
        no runtime app at all.
      '';
    };

    unsupportedReason = mkOption {
      type = types.str;
      default = unsupportedReasons.${game.runtime} or "";
      defaultText = lib.literalMD "derived from `runtime`";
      description = ''
        Shown by the client in place of a Play button when
        `backend = "unsupported"`. Say why, not just that.
      '';
    };

    retroarchCore = mkOption {
      type = types.nullOr types.str;
      default = if game.runtime == "retroarch" then derivedCore else null;
      defaultText = lib.literalMD "derived from `retroarch.cores`";
      description = ''
        Core filename as RetroArch Android names it, e.g.
        `melonds_libretro_android.so`. The client sideloads the matching
        core through RetroArch's exported CoreSideloadActivity before
        launching.
      '';
    };

    containerConfig = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.str
          types.bool
          types.int
        ]
      );
      default = { };
      description = ''
        Per-game overrides merged over the computed
        `app.gamenative.LAUNCH_GAME` `container_config` JSON. Only the
        keys GameNative's IntentLaunchManager.parseContainerConfig
        actually reads take effect (screenSize, envVars, graphicsDriver,
        dxwrapper, dxwrapperConfig, wincomponents, execArgs,
        executablePath, box64Preset, videoMemorySize, ...); unknown keys
        are silently ignored on the device side. Note that wineVersion,
        emulator (box64 vs FEX) and the container variant are NOT
        settable over the intent.

        `executablePath` is always sent, derived from `game.executable`,
        so do not set it here. Overriding it would create a second
        source of truth for the launch target.
      '';
    };

    padKeys = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        a = "X";
        b = "C";
        dpad = "arrows";
        leftStick = "arrows";
      };
      description = ''
        Physical gamepad buttons mapped to keyboard keys, for a game that
        reads the keyboard but not GameNative's virtual XInput pad. Empty
        means the pad reaches the game as XInput, which is right for
        anything modern.

        The case this exists for: a DirectInput-era title. `dinput.dll`
        games see no pad under GameNative at all -- its pad support is
        XInput-shaped (winhandler feeds a virtual XInput device) and wine's
        own dinput enumerates winebus, which has no devices there -- while
        keys injected into the X server do arrive. So the pad is mapped to
        whatever keys the game itself reads; those are a property of the
        game and belong here, not in a hand-made profile on the phone.

        Buttons: `a b x y l1 r1 l2 r2 l3 r3 start select`, plus `dpad`
        and `leftStick` / `rightStick`, which take the four-way value
        `arrows` (or `wasd`). Keys: a single letter or digit, or one of
        `UP DOWN LEFT RIGHT ENTER ESC SPACE TAB BKSP DEL SHIFT CTRL ALT`.

        Travels in the manifest as `gamenative.padKeys`; the client builds
        GameNative's controls profile from it and installs it through the
        registration intent when the runtime accepts one, else writes it
        beside the game for a one-time import.
      '';
    };

    payload = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            cid = mkOption {
              type = types.str;
              description = ''
                CID the client fetches. A directory CID (`ipfs add -r
                --raw-leaves` of `outputs.payload`) for a built tree, a
                file CID for a game that is one already-pinned file.
              '';
            };

            name = mkOption {
              type = types.str;
              default = "";
              description = ''
                File name to give a single-file payload once fetched.
                Empty for a directory payload, whose DAG carries its own
                names.
              '';
            };

            sha256 = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Content hash of a single-file payload. Null for a
                directory payload: the DAG CID already verifies every
                block on the way in, and a tree has no one file to hash,
                so the client must not demand one.
              '';
            };
          };
        }
      );
      default =
        let
          srcs = game.ipfsSources or [ ];
          only = builtins.head srcs;
          singleFileBackends = builtins.elem game.android.backend [
            "retroarch"
            "azahar"
          ];
        in
        # A game that builds nothing has nothing to pin. With no
        # buildScript, mkGame copies the single fetched file to
        # `$out/<src.name>`, so the tree the phone needs is byte-for-byte
        # the archive already pinned as `src`, and `outputs.payload` would
        # only republish those same bytes under a second CID. Requiring
        # the name to equal `executable` keeps the manifest's `rom` and
        # the payload agreeing about what to open.
        #
        # True of any backend whose game is one file the emulator opens --
        # a libretro ROM and a 3DS dump are the same shape here.
        #
        # Everything else is excluded and still needs its built tree
        # pinned by hand: a recipe that unzips or patches produces bytes
        # that exist nowhere yet, and a PSX game carries a second source
        # (the BIOS) that the payload would have to include.
        if
          singleFileBackends
          && game.buildScript == ""
          && builtins.length srcs == 1
          && (only.name or null) == game.executable
        then
          {
            inherit (only) cid name;
            sha256 = only.outputHash;
          }
        else
          null;
      defaultText = lib.literalMD "the game's own pinned source, for a single-file game that builds nothing; otherwise `null`";
      description = ''
        The published Android payload: the pinned CID of the tree
        `outputs.payload` builds. Defaults to the game's own pinned
        source for a single-file game that builds nothing, because there
        the two are the same bytes (see the comment above). Otherwise
        null until the operator has tested the game on a device and
        pinned the artifact -- same stage-then-pin discipline as a
        game's `src` (see AGENTS.md). When null the manifest omits
        `payload` and the client lists the game as not yet available on
        Android.
      '';
    };

    layers = mkOption {
      type = types.listOf types.attrs;
      internal = true;
      default = lib.reverseList game.modLayers;
      defaultText = lib.literalMD "`lib.reverseList game.modLayers`";
      description = ''
        One artifact per opt-in mod, so a phone can toggle mods without
        re-fetching the multi-GB base tree.

        Not declared per game: this IS the game's `modLayers`, the same
        list the desktop overlay selects its lowers from, so what a player
        is offered on a phone cannot drift from what actually gets mounted.
        Reversed because `lowers` is highest-priority-first while the
        client extracts lowest-priority-first, unpacking `payload` and then
        each selected layer in list order with later files winning. That
        reproduces the overlay's merge exactly, because a mod tree only
        ever adds or wins a path -- it has no whiteouts, so nothing a lower
        layer wrote can need deleting. Same reasoning as `outputs.payload`,
        which flattens the identical order.
      '';
    };

    outputs.payload = mkOption {
      type = types.package;
      description = ''
        The game's installed worktree, exactly as the desktop overlay
        presents it, for the operator to pin:
        `nix build .#androidPayloads.<slug>` then
        `ipfs add -r --raw-leaves` the result, which yields the single
        directory CID that goes into `android.payload.cid`.

        A directory, not an archive. The client fetches a CAR and
        verifies the DAG block by block, so what it reconstructs is a
        UnixFS tree; it has no archive reader and never needs one. This
        is also what makes multi-file games expressible at all -- a
        multi-disc set is its `.chd` files beside the `.m3u` that lists
        them, and a single-file ROM is just the degenerate case of the
        same shape.
      '';
    };

    outputs.manifest = mkOption {
      type = types.package;
      description = ''
        JSON descriptor of how this game reaches Android. Schema and
        consumer contract: docs/android.md.
      '';
    };

    outputs.manifestAttrs = mkOption {
      type = types.attrs;
      internal = true;
      description = ''
        The manifest before serialisation. Exists so
        `scripts/sync-metadata.nix` can project it into each game's
        `metadata.json` by plain evaluation; reading `outputs.manifest`
        instead would make the sync an import-from-derivation across
        every game in the catalog. `outputs.manifest` is its JSON.
      '';
    };

    outputs.apk = mkOption {
      type = types.package;
      description = ''
        The signed APK derivation. No default: only games with a real
        self-contained Android build define this, with their own
        packaging pipeline (see games/balatro/apk.nix for the
        balatromobile-based LOVE2D example). Evaluating it for a game
        that doesn't define it is an error.
      '';
    };
  };

  config = {
    outputs.payload =
      pkgs.runCommand "${game.name}-android-tree"
        {
          passthru = {
            gameData = game._gameData;
            inherit (game.bwrap.overlay) lowers;
          };
        }
        ''
          mkdir -p "$out"

          # The payload must be what the desktop overlay presents, not just
          # _gameData: recipes stack mods and other trees above it as extra
          # fuse-overlayfs lowers (lib/mk-game.nix `overlay.lowers`, first =
          # highest priority). Copy lowest priority first so higher ones
          # overwrite, which reproduces the overlay's merge order. Without
          # this, half-life-uplink would ship vanilla Half-Life.
          #
          # -L dereferences: a recipe may symlink discs in from the store
          # (games/final-fantasy-vii does), and a symlink into /nix/store
          # means nothing on a phone.
          ${lib.concatMapStringsSep "\n" (l: ''
            cp -rL --no-preserve=mode,ownership,timestamps -T "${l}" "$out"
          '') (lib.reverseList game.bwrap.overlay.lowers)}

          chmod -R u+w "$out"
          test -n "$(ls -A "$out")" \
            || (echo "android: empty payload for ${game.name}" >&2; exit 1)
        '';

    outputs.manifestAttrs =
      let
        # Values the client assumes when a key is absent. Emitting them
        # per game costs ~15 KB across the catalog and says nothing: they
        # are identical for all 269 gamenative entries. Documented as
        # defaults in docs/android.md so the client and this file agree.
        #
        # No screen size here. It is a property of the device, not the
        # game, and the client sends the panel it is running on; a value
        # from this file is the recipe author's panel, not the player's
        # -- measured, a "phone-shaped" 1280x720 sent from here put a
        # 1080p panel into a scaled, decorated window. Leaving the key
        # out of the intent does not help either: GameNative's own
        # default buckets the aspect ratio and gives every 16:9 device
        # 1280x720. A game that genuinely needs a size sets
        # `containerConfig.screenSize` itself.
        containerDefaults = {
          execArgs = "";
          dxwrapper = "dxvk";
        };
        container = {
          # game.executable is the single source of truth for the
          # launch target, so hand it straight to GameNative rather
          # than letting CustomGameScanner rediscover it by scanning
          # the folder. getLaunchExecutable prefers this value when
          # the file exists relative to the A: drive and falls back
          # to its own scan otherwise, so sending it is strictly
          # more robust than omitting it.
          executablePath = game.executable;
          execArgs = lib.concatStringsSep " " game.executableArgs;
          dxwrapper = "dxvk";
        }
        // game.android.containerConfig;
      in
      {
        schema = 1;
        slug = game.name;
        inherit (game) runtime;
        backend = game.android.backend;
      }
      # Absent means "not published for Android"; there is no third state,
      # so an explicit null on 400-odd games is dead weight. Same for the
      # optional-layer and settings lists: a game with no mods and no
      # player-facing options says so by omission.
      // lib.optionalAttrs (game.android.payload != null) {
        inherit (game.android) payload;
      }
      // lib.optionalAttrs (game.android.layers != [ ]) {
        layers = map (
          l:
          {
            inherit (l)
              name
              key
              value
              cid
              ;
          }
          // lib.optionalAttrs (l.requires != null) { inherit (l) requires; }
          // lib.optionalAttrs (l.size != null) { inherit (l) size; }
        ) game.android.layers;
      }
      # Verbatim `passthru.settingsSchema`, the same list the couch
      # launcher renders, so the phone's options screen and the desktop's
      # cannot drift.
      // lib.optionalAttrs (settingsSchema != [ ]) {
        settings = settingsSchema;
      }
      // lib.optionalAttrs (game.android.backend == "unsupported") {
        reason = game.android.unsupportedReason;
      }
      // lib.optionalAttrs (game.android.backend == "gamenative") {
        gamenative =
          let
            buttons = [
              "a"
              "b"
              "x"
              "y"
              "l1"
              "r1"
              "l2"
              "r2"
              "l3"
              "r3"
              "start"
              "select"
              "dpad"
              "leftStick"
              "rightStick"
            ];
            bad = lib.filter (b: !(lib.elem b buttons)) (lib.attrNames game.android.padKeys);
          in
          {
            containerConfig = lib.filterAttrs (
              k: v: !(containerDefaults ? ${k}) || containerDefaults.${k} != v
            ) container;
          }
          // lib.optionalAttrs (game.android.padKeys != { }) {
            padKeys =
              if bad != [ ] then
                throw "${game.name}: android.padKeys has no such button: ${lib.concatStringsSep ", " bad}"
              else
                game.android.padKeys;
          };
      }
      // lib.optionalAttrs (game.android.backend == "retroarch") {
        retroarch = {
          core = game.android.retroarchCore;
          rom = game.executable;
          coreOptions = game.retroarch.coreOptions;
        };
      }
      // lib.optionalAttrs (game.android.backend == "dolphin") {
        dolphin.disc = game.executable;
      }
      // lib.optionalAttrs (game.android.backend == "azahar") {
        azahar.rom = game.executable;
      };

    outputs.manifest = pkgs.writeText "${game.name}-android.json" (
      builtins.toJSON game.android.outputs.manifestAttrs
    );
  };
}
