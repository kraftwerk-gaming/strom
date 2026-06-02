# mkGame: compose a strom game from typed wrapperModules.
#
# Returns the evaluated wrapperModule; build derivation is
# `<game>.outputs.wrapper`. Mods/overrides via `.apply { ... }` or
# `.extend { ... }`.
#
# Composition (inside-out):
#   proton    : exe -> proton -> gamescope -> bwrap [FHS multilib + overlay]
#   native    : exe -> gamescope -> bwrap          [FHS + overlay]
#   custom    : exe -> gamescope -> bwrap          [FHS + overlay]
#   retroarch : rom -> retroarch -> bwrap
#   pcsx2     : iso -> pcsx2 -> bwrap
#
# Single outer bwrap call handles FHS at /usr (strom-fhs.nix). The
# read-write overlay over the nix-store game data is mounted on the host
# with patched fuse-overlayfs (kernel --overlay can't make 0555 store
# lowers writable in this single-uid userns) and bind-mounted into the
# sandbox. No nested buildFHSEnv.
{
  lib,
  pkgs,
  wrappers,
  fetchIpfs,
}:

gameSpec:

let
  inherit (lib) mkOption types;
  wlib = wrappers.lib;

  # submoduleWith over the wrapper-base modules plus a raw wrapper
  # source. `extraDefaults` is a module that sets strom-specific
  # universals — it merges per-key (unlike mkOption.default, which
  # gets replaced once anything touches the submodule).
  wrapperType =
    src: extraDefaults:
    types.submoduleWith {
      specialArgs = { inherit wlib fetchIpfs; };
      modules = [
        wlib.modules.wrapper
        wlib.modules.meta
        src
        { config.pkgs = pkgs; }
        extraDefaults
      ];
    };

  gameModule =
    { config, lib, ... }:
    let
      cfg = config;
      # No quotes here: wrapPackage's escapeShellArgWithEnv adds its
      # own, and literal quotes leak into the filename wine sees.
      overlayExe =
        if lib.hasPrefix "/" cfg.executable then cfg.executable else "$STROM_OVERLAY/${cfg.executable}";
    in
    {
      _class = "wrapper";

      options = {
        name = mkOption {
          type = types.str;
          description = "Game name (used for ~/.strom/<name>).";
        };
        src = mkOption {
          type = types.package;
        };
        runtime = mkOption {
          type = types.enum [
            "proton"
            "native"
            "custom"
            "retroarch"
            "pcsx2"
          ];
          default = "custom";
        };
        executable = mkOption {
          type = types.str;
          default = "";
          description = "Path inside the overlay (or absolute) to launch.";
        };
        executableArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        buildScript = mkOption {
          type = types.lines;
          default = "";
        };
        nativeBuildInputs = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        preRun = mkOption {
          type = types.lines;
          default = "";
        };
        runScript = mkOption {
          type = types.nullOr types.lines;
          default = null;
        };
        saveLocations = mkOption {
          type = types.listOf types.str;
          description = ''
            Paths under drive_c/users/steamuser/ that get relocated to
            ~/.strom/<name>/ so prefix wipes don't take user progress.
            Required for runtime = "proton"; set to [ ] only if the
            engine writes saves next to its binary (those persist via
            the overlay upper).
          '';
          default =
            if cfg.runtime == "proton" then
              throw "strom: ${cfg.name}: saveLocations must be set explicitly for runtime = \"proton\" (set to [ ] only if the engine writes saves next to its binary in the overlay; see AGENTS.md \"Save preservation\")"
            else
              [ ];
          defaultText = lib.literalMD ''
            `[ ]` for non-proton runtimes; throws for `runtime = "proton"`
            unless set explicitly.
          '';
        };
        copyGlobs = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        targetPkgs = mkOption {
          type = types.functionTo (types.listOf types.package);
          default = _: [ ];
        };
        ipfsSources = mkOption {
          type = types.listOf types.package;
          default = [ cfg.src ] ++ lib.optionals (cfg.runtime == "pcsx2") [ cfg.pcsx2.bios ];
          defaultText = lib.literalMD "`[ src ]` plus the PS2 BIOS for `runtime = pcsx2`.";
        };

        # Extracted game data; the overlay's lower layer.
        _gameData = mkOption {
          type = types.package;
          internal = true;
          default = pkgs.runCommandLocal "${cfg.name}-data" { inherit (cfg) nativeBuildInputs src; } (
            if cfg.buildScript != "" then
              cfg.buildScript
            else
              ''
                mkdir -p $out
                if [ -d "$src" ]; then
                  cp -r "$src"/. $out/
                else
                  cp "$src" "$out/${cfg.src.name or "src"}"
                fi
              ''
          );
        };

        bwrap = mkOption {
          type = wrapperType ./bwrap.nix {
            config = {
              binName = cfg.name;
              unshare-pid = true;
              die-with-parent = true;
              chdir = "/";
              ro-bind."/" = "/";
              dev-bind."/dev" = "/dev";
              proc = [ "/proc" ];

              # FHS userspace at /usr — extended in proton's mkIf.
              fhsTargetPkgs = cfg.targetPkgs;

              # /tmp must come before --tmpfs /tmp/.X11-unix.
              bind = {
                "/tmp" = "/tmp";
                "/run" = "/run";
              };
              # The host /tmp/.X11-unix is root-owned, so the sandbox
              # user can't write a new socket there. Tmpfs the dir,
              # then ro-bind-try numbered host sockets on top.
              tmpfs = [ "/tmp/.X11-unix" ];
              chmod."/tmp/.X11-unix" = "1777";
              # bind-try (post-tmpfs): paths inside a tmpfs'd parent.
              # Proton tmpfs's $HOME, so STROM_* must land here.
              bind-try = {
                "$STROM_GAMEDIR" = "$STROM_GAMEDIR";
                "$STROM_COMPATDATA" = "$STROM_COMPATDATA";
                "$STROM_CACHEDIR" = "$STROM_CACHEDIR";
                # Per-game umu/protonfixes cache. umu-protonfixes' logger
                # appends to $XDG_CACHE_HOME/umu-protonfixes/protonfixes_test.log
                # (XDG_CACHE_HOME unset -> $HOME/.cache) on every launch
                # (including the PROTONFIXES_DISABLE=1 "unit test" skip path);
                # a single shared host dir means concurrent Proton games race
                # on that file. Bind a private per-game source onto the shared
                # in-sandbox path so each game gets its own umu state, mirroring
                # the per-launch private XDG_RUNTIME_DIR in lib/gamescope.nix.
                "$HOME/.cache/umu" = "$STROM_CACHEDIR/umu";
                "$HOME/.cache/umu-protonfixes" = "$STROM_CACHEDIR/umu-protonfixes";
                "$HOME/.cache/wine" = "$HOME/.cache/wine";
              };
              ro-bind-try = lib.genAttrs (lib.genList (n: "/tmp/.X11-unix/X${toString n}") 10) (p: p) // {
                "$HOME/.local/share/vulkan" = "$HOME/.local/share/vulkan";
              };

              # /tmp/.strom-overlay (not /strom/overlay) because the
              # base --ro-bind / / makes / read-only and bwrap can't
              # mkdir a top-level mountpoint there. /tmp is RW from
              # the earlier --bind /tmp /tmp. The merged tree is mounted
              # on the host with fuse-overlayfs (see bwrap.nix) and
              # bind-mounted here.
              # Default lowers = [_gameData]; recipes layer mods /
              # soundtracks / etc. on top via `lib.mkBefore [...]` on
              # this same option (first = highest priority).
              overlay = {
                lowers = [ "${cfg._gameData}" ];
                upper = "$STROM_GAMEDIR";
                work = "$STROM_CACHEDIR/overlay-work";
                dest = "/tmp/.strom-overlay";
              };

              preHook = ''
                STROM_GAMEDIR="''${HOME:-.}/.strom/${cfg.name}"
                STROM_COMPATDATA="''${HOME:-.}/.strom/.compatdata/${cfg.name}"
                STROM_CACHEDIR="''${HOME:-.}/.cache/strom/${cfg.name}"
                STROM_OVERLAY=/tmp/.strom-overlay
                export STROM_GAMEDIR STROM_COMPATDATA STROM_CACHEDIR STROM_OVERLAY
                mkdir -p "$STROM_GAMEDIR" "$STROM_COMPATDATA" "$STROM_CACHEDIR" \
                  ${lib.optionalString (cfg.runtime == "proton") ''
                    "$STROM_CACHEDIR/umu" "$STROM_CACHEDIR/umu-protonfixes" "$HOME/.cache/wine"
                  ''}
                # fuse-overlayfs needs an empty workdir on the same fs as
                # upper. overlayfs creates the work/ subdir as mode 0000
                # (owned by our uid but unreadable), so a plain `rm -rf`
                # fails with EACCES on relaunch. chmod ourselves in first.
                if [ -d "$STROM_CACHEDIR/overlay-work" ]; then
                  chmod -R u+rwX "$STROM_CACHEDIR/overlay-work" 2>/dev/null || true
                fi
                rm -rf "$STROM_CACHEDIR/overlay-work"
                mkdir -p "$STROM_CACHEDIR/overlay-work"

                ${lib.optionalString (cfg.runtime == "proton") ''
                  exec 9>"$STROM_CACHEDIR/.lock"
                  if ! flock -n 9; then
                    echo "${cfg.name}: another instance is already running" >&2
                    echo "if no instance is running, remove the stale lock:" >&2
                    echo "  rm $STROM_CACHEDIR/.lock" >&2
                    exit 1
                  fi
                ''}

                ${lib.optionalString (cfg.copyGlobs != [ ]) ''
                  # Materialize files Wine/Proton can't copy-up cleanly
                  # (mmap+MAP_PRIVATE writes break overlayfs copy-up).
                  ${lib.concatMapStringsSep "\n" (g: ''
                    if [ ! -e "$STROM_GAMEDIR/${g}" ] && [ -e "${cfg._gameData}/${g}" ]; then
                      mkdir -p "$STROM_GAMEDIR/$(dirname "${g}")"
                      cp -r "${cfg._gameData}/${g}" "$STROM_GAMEDIR/${g}"
                      chmod -R u+w "$STROM_GAMEDIR/${g}"
                    fi
                  '') cfg.copyGlobs}
                ''}

                # gamescope/Xwayland writes its PID into /tmp/.Xn-lock,
                # but ours run inside --unshare-pid so the namespaced
                # PIDs collide with every fresh ns. Check the abstract
                # X socket in /proc/net/unix (net ns is shared) and
                # delete stale locks.
                for __strom_xlock in /tmp/.X[0-9]*-lock; do
                  [ -e "$__strom_xlock" ] || continue
                  [ -O "$__strom_xlock" ] || continue
                  __strom_n=''${__strom_xlock#/tmp/.X}
                  __strom_n=''${__strom_n%-lock}
                  if ! grep -qF "@/tmp/.X11-unix/X$__strom_n" /proc/net/unix; then
                    rm -f "$__strom_xlock"
                  fi
                done

                ${lib.optionalString cfg.padToKb.enable ''
                  # Gamepad->keyboard remapper on the host (uinput is
                  # outside the sandbox; the synthesized /dev/input/
                  # eventN reaches inside via --dev-bind /dev /dev).
                  STROM_PAD_TO_KB_EVSIEVE=${lib.getExe cfg.padToKb.package}
                  STROM_PAD_TO_KB_DEVICE_GLOBS=${lib.escapeShellArg (lib.concatStringsSep " " cfg.padToKb.inputDevices)}
                  STROM_PAD_TO_KB_VIRTUAL_NAME=${lib.escapeShellArg cfg.padToKb.virtualName}
                  STROM_PAD_TO_KB_MAPPING_ARGS=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.padToKb.mappingArgs)})
                  export STROM_PAD_TO_KB_EVSIEVE STROM_PAD_TO_KB_DEVICE_GLOBS STROM_PAD_TO_KB_VIRTUAL_NAME
                  ${builtins.readFile ./pad-to-kb-launcher.sh}
                ''}
              '';
              # Inner script (inside bwrap): cd to overlay, shader
              # cache, preRun, exec the runtime entrypoint.
              command = "${pkgs.writeShellScript "${cfg.name}-inner" ''
                set -euo pipefail
                export GAMEDIR="$STROM_OVERLAY"
                cd "$GAMEDIR"

                GAMECACHE="''${HOME:-.}/.cache/strom/${cfg.name}/shadercache"
                mkdir -p "$GAMECACHE"
                export MESA_SHADER_CACHE_DIR="$GAMECACHE"
                export DXVK_STATE_CACHE_PATH="$GAMECACHE"

                ${cfg.preRun}
                exec ${cfg.entrypoint} ${lib.escapeShellArgs cfg.executableArgs} "$@"
              ''}";
            };
          };
        };

        gamescope = mkOption {
          type = wrapperType ./gamescope.nix { };
        };

        proton = mkOption {
          type = wrapperType ./proton.nix {
            config = {
              compatDataPath = "\${HOME:-.}/.strom/.compatdata/${cfg.name}/0";
              saveLocations = cfg.saveLocations;
            };
          };
        };

        retroarch = mkOption {
          type = wrapperType ./retroarch.nix {
            config.settings = {
              input_autodetect_enable = "true";
              input_joypad_driver = "sdl2";
              pause_nonactive = "false";
              video_driver = "vulkan";
              video_fullscreen = "false";
              video_windowed_fullscreen = "false";
            };
          };
        };

        # The path the inner bwrap script execs.
        entrypoint = mkOption {
          type = types.either types.path types.str;
          internal = true;
        };

        pcsx2 = mkOption {
          type = wrapperType ./pcsx2.nix { };
        };

        padToKb = mkOption {
          type = wrapperType ./pad-to-kb.nix { };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.runtime == "proton") {
          # /sys ro-bind for vulkan/wayland device probing; tmpfs $HOME
          # so proton.preHook can write ~/.steam/sdk{32,64}/.
          bwrap.ro-bind."/sys" = "/sys";
          bwrap.tmpfs = [ "$HOME" ];

          # Extend the universal FHS with proton's graphics/audio stack
          # and turn on multilib (/usr/lib32 for 32-bit Wine).
          bwrap.fhsTargetPkgs = lib.mkForce (p: cfg.proton.fhsTargetPkgs p ++ cfg.targetPkgs p);
          bwrap.fhsMultilib = true;

          proton.exe = overlayExe;
          proton.env = cfg.env;
          gamescope.command = lib.getExe cfg.proton.outputs.wrapper;
          entrypoint = lib.getExe cfg.gamescope.outputs.wrapper;
        })

        (lib.mkIf (cfg.runtime == "native") {
          # $STROM_GAMEDIR -> $HOME so XDG saves persist.
          bwrap.bind."$HOME" = "$STROM_GAMEDIR";
          bwrap.env = cfg.env;

          # Inner command is gamescope. If a runScript is set it
          # becomes the inner command (for env exports / mkdir / config
          # bootstrap before the real exec); otherwise gamescope wraps
          # the executable directly.
          gamescope.command =
            if cfg.runScript != null then
              "${pkgs.writeShellScript "${cfg.name}-runscript" cfg.runScript}"
            else
              overlayExe;
          entrypoint = lib.getExe cfg.gamescope.outputs.wrapper;
        })

        (lib.mkIf (cfg.runtime == "retroarch") {
          retroarch.romPath = overlayExe;
          entrypoint = lib.getExe cfg.retroarch.outputs.wrapper;
        })

        (lib.mkIf (cfg.runtime == "pcsx2") {
          pcsx2.isoPath = overlayExe;
          entrypoint = lib.getExe cfg.pcsx2.outputs.wrapper;
        })

        (lib.mkIf (cfg.runtime == "custom") {
          # Like native (HOME -> $STROM_GAMEDIR); FHS at /usr is on by
          # default for bare-soname dlopen of bundled libs.
          # `bwrap.fhsMultilib = true` opt-in for 32-bit games.
          bwrap.bind."$HOME" = "$STROM_GAMEDIR";
          bwrap.env = cfg.env;

          gamescope.command =
            if cfg.runScript != null then
              "${pkgs.writeShellScript "${cfg.name}-runscript" cfg.runScript}"
            else
              overlayExe;
          entrypoint = lib.getExe cfg.gamescope.outputs.wrapper;
        })

        # Final derivation: bwrap.outputs.wrapper with pname/passthru/meta.
        {
          outputs.wrapper = cfg.bwrap.outputs.wrapper.overrideAttrs (old: {
            pname = cfg.name;
            passthru = (old.passthru or { }) // {
              runtime = cfg.runtime;
              ipfsSources = cfg.ipfsSources;
            };
            meta = (old.meta or { }) // gameMeta;
          });
        }
      ];
    };

  # Free-form meta (the wrapper-base meta schema only accepts
  # maintainers+platforms; games set description/mainProgram/...).
  gameMeta = gameSpec.meta or { };
  cleanedSpec = removeAttrs gameSpec [ "meta" ];

  configured = (wlib.wrapModule gameModule).apply cleanedSpec;
in
configured
