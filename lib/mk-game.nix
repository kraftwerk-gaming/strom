# mkGame: build a strom game as a composition of typed wrapperModules.
#
# Returns the configured wrapperModule (the evaluated `config` of the
# composed module set). Consumers reach the built derivation via
# `<game>.outputs.wrapper`; mods/overrides go through `.apply { ... }`
# or `.extend { ... }`, which re-evaluate the module with extra
# definitions merged in.
#
# mkGame is its own wrapperModule. Game-level options (name, src,
# executable, runtime, ...) sit alongside typed sub-wrapper sub-options
# (bwrap, fhs, gamescope, proton, retroarch, pcsx2), each a submoduleWith
# over the corresponding raw module source from this directory.
#
# Composition (inside-out):
#   proton    : exe -> proton -> gamescope -> fhs -> bwrap
#   native    : exe -> gamescope -> bwrap
#   retroarch : rom -> retroarch -> bwrap
#   pcsx2     : iso -> pcsx2 -> bwrap
#   custom    : exe -> gamescope -> fhs -> bwrap   (when runScript is null)
#   custom    : runScript -> fhs -> bwrap          (when runScript is set;
#                                                   the script invokes gamescope itself)
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

  # submoduleWith over the wrapper-base modules + a raw wrapper source.
  # pkgs is plumbed in via the modules list. `extraDefaults` is an
  # additional module the caller can use to set strom-specific universals
  # (binName, unshare-pid, ...) — these go in the modules list so they
  # merge per-key with the outer-mkGame config block's settings (unlike
  # mkOption.default values which get replaced wholesale once any outer
  # definition touches the submodule). fetchIpfs is passed as a special
  # arg so sub-wrappers (currently pcsx2) can fetch their own assets.
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
      # Don't pre-wrap relative paths in quotes here — when this value
      # flows through wrapPackage's args, escapeShellArgWithEnv adds its
      # own quotes around it, and literal quotes become part of the
      # filename wine sees. Templates that interpolate config.command/
      # exe/etc directly add their own "..." wrapping.
      overlayExe =
        if lib.hasPrefix "/" cfg.executable then cfg.executable else "$STROM_OVERLAY/${cfg.executable}";

      # X11 socket bind: tmpfs the dir to own it as the sandbox user, then
      # ro-bind-try each numbered socket statically. Only the existing ones
      # mount; --ro-bind-try is silent on missing srcs.
      x11Binds = lib.genAttrs (lib.genList (n: "/tmp/.X11-unix/X${toString n}") 10) (p: p);
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
            Paths (relative to `drive_c/users/steamuser/`) inside the
            wineprefix that should be relocated to `~/.strom/<name>/`
            so prefix wipes don't take user progress with it.

            Required for `runtime = "proton"`. Set to `[ ]` explicitly
            if the game writes saves *next to its binary* inside the
            fuse-overlayfs upper (where they already persist). For
            non-proton runtimes (`native`, `custom`, `retroarch`,
            `pcsx2`) the bind-mount or emulator semantics handle save
            persistence independently — this option is moot and
            defaults to `[ ]`.
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

        # Build-side: extracted game data (consumed as fuse-overlayfs lower).
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

        # Sub-wrapper sub-options. The second arg to wrapperType is an
        # extra module with strom-specific universals (settings that apply
        # regardless of runtime). Per-runtime tweaks merge in via the
        # config block below.
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
              # bind (pre-tmpfs): independent paths or parents of a tmpfs
              #   target. /tmp must come before --tmpfs /tmp/.X11-unix.
              # bind-try (post-tmpfs): paths inside a tmpfs'd parent.
              #   The $STROM_* dirs all live under $HOME, which the proton
              #   runtime tmpfs's; they must land here so the tmpfs doesn't
              #   wipe them. (Other runtimes don't tmpfs $HOME and the
              #   position is irrelevant.)
              bind = {
                "/tmp" = "/tmp";
                "/run" = "/run";
              };
              bind-try = {
                "$STROM_GAMEDIR" = "$STROM_GAMEDIR";
                "$STROM_COMPATDATA" = "$STROM_COMPATDATA";
                "$STROM_CACHEDIR" = "$STROM_CACHEDIR";
                "$HOME/.cache/umu" = "$HOME/.cache/umu";
                "$HOME/.cache/umu-protonfixes" = "$HOME/.cache/umu-protonfixes";
                "$HOME/.cache/wine" = "$HOME/.cache/wine";
              };
              ro-bind-try = {
                "$HOME/.local/share/vulkan" = "$HOME/.local/share/vulkan";
              };
              # Strom-outer setup (runs outside bwrap in the wrapper bash):
              # STROM_* dirs, optional flock for proton, fuse-overlayfs
              # mount, fusermount cleanup trap.
              preHook = ''
                STROM_GAMEDIR="''${HOME:-.}/.strom/${cfg.name}"
                STROM_COMPATDATA="''${HOME:-.}/.strom/.compatdata/${cfg.name}"
                STROM_CACHEDIR="''${HOME:-.}/.cache/strom/${cfg.name}"
                export STROM_GAMEDIR STROM_COMPATDATA STROM_CACHEDIR
                mkdir -p "$STROM_GAMEDIR" "$STROM_COMPATDATA" "$STROM_CACHEDIR" \
                  ${lib.optionalString (cfg.runtime == "proton") ''
                    "$HOME/.cache/umu" "$HOME/.cache/umu-protonfixes" "$HOME/.cache/wine"
                  ''}

                ${lib.optionalString (cfg.runtime == "proton") ''
                  # Single-instance lock per game guards the wineprefix.
                  # flock locks are tied to the OFD; FD 9 is closed (`9<&-`)
                  # in the fuse-overlayfs daemon below so it doesn't keep
                  # the lock alive after wrapper exit.
                  exec 9>"$STROM_CACHEDIR/.lock"
                  if ! flock -n 9; then
                    echo "${cfg.name}: another instance is already running" >&2
                    echo "if no instance is running, remove the stale lock:" >&2
                    echo "  rm $STROM_CACHEDIR/.lock" >&2
                    exit 1
                  fi
                ''}

                # Sweep stale /tmp/.X{1..32}-lock files. gamescope/Xwayland
                # writes its running PID into these locks, then on the next
                # start does `kill -0 <pid>`. We run gamescope inside bwrap
                # with --unshare-pid, so the lock PIDs are namespaced (1,2,
                # 11,…) — values present in every fresh pid-namespace too,
                # making every slot appear taken ("No display available in
                # the first 33"). Check the abstract X socket instead: the
                # net namespace is shared with the host, so a *bound*
                # `@/tmp/.X11-unix/Xn` shows up in /proc/net/unix and means
                # the slot is genuinely in use by a parallel game.
                for __strom_xlock in /tmp/.X[0-9]*-lock; do
                  [ -e "$__strom_xlock" ] || continue
                  [ -O "$__strom_xlock" ] || continue
                  __strom_n=''${__strom_xlock#/tmp/.X}
                  __strom_n=''${__strom_n%-lock}
                  if ! grep -qF "@/tmp/.X11-unix/X$__strom_n" /proc/net/unix; then
                    rm -f "$__strom_xlock"
                  fi
                done

                # Mount the read-write overlay over the nix-store game data.
                STROM_OVERLAY=$(${lib.getExe cfg.fuseOverlayfs.outputs.wrapper} "$STROM_GAMEDIR" 9<&-)
                export STROM_OVERLAY

                # --die-with-parent + --unshare-pid on bwrap handle process
                # cleanup, but the fuse overlay must be unmounted explicitly.
                trap 'fusermount -uz "$STROM_OVERLAY" 2>/dev/null || true' EXIT INT TERM

                ${lib.optionalString cfg.padToKb.enable ''
                  # Launch the gamepad->keyboard remapper on the host
                  # (uinput access lives outside the bwrap sandbox; the
                  # synthesized /dev/input/eventN is visible inside via
                  # the existing --dev-bind /dev /dev). The launcher
                  # body lives in lib/pad-to-kb-launcher.sh and is
                  # inlined here so shellcheck on the wrapper sees it.
                  STROM_PAD_TO_KB_EVSIEVE=${lib.getExe cfg.padToKb.package}
                  STROM_PAD_TO_KB_DEVICE_GLOBS=${lib.escapeShellArg (lib.concatStringsSep " " cfg.padToKb.inputDevices)}
                  STROM_PAD_TO_KB_VIRTUAL_NAME=${lib.escapeShellArg cfg.padToKb.virtualName}
                  STROM_PAD_TO_KB_MAPPING_ARGS=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.padToKb.mappingArgs)})
                  export STROM_PAD_TO_KB_EVSIEVE STROM_PAD_TO_KB_DEVICE_GLOBS STROM_PAD_TO_KB_VIRTUAL_NAME
                  ${builtins.readFile ./pad-to-kb-launcher.sh}
                ''}
              '';
              # Inner script runs INSIDE bwrap: cd into the overlay, set
              # up the shader cache, run preRun, exec the chain root.
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

        fhs = mkOption {
          type = wrapperType ./fhs-user-env.nix {
            config.binName = "${cfg.name}-fhs";
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

        fuseOverlayfs = mkOption {
          type = wrapperType ./fuse-overlayfs.nix {
            config = {
              gameFiles = cfg._gameData;
              copyGlobs = cfg.copyGlobs;
            };
          };
        };

        # Path the inner bwrap script execs after setting up GAMEDIR /
        # shadercache / preRun. Set in the per-runtime mkIf block below
        # (one line each).
        entrypoint = mkOption {
          type = types.either types.path types.str;
          internal = true;
          description = "Path the inner bwrap script execs.";
        };

        pcsx2 = mkOption {
          type = wrapperType ./pcsx2.nix { };
        };

        padToKb = mkOption {
          type = wrapperType ./pad-to-kb.nix { };
        };
      };

      # Runtime-specific bits, one block per runtime. Read each (lib.mkIf
      # ...) block to see exactly what that runtime adds on top of the
      # universals defined in the sub-wrapper option modules above.
      config = lib.mkMerge [
        (lib.mkIf (cfg.runtime == "proton") {
          # /sys ro-bind for vulkan/wayland device probing; tmpfs $HOME so
          # proton.preHook can write ~/.steam/sdk{32,64}/steamclient.so.
          bwrap.ro-bind."/sys" = "/sys";
          bwrap.tmpfs = [ "$HOME" ];

          proton.exe = overlayExe;
          proton.env = cfg.env;
          gamescope.command = lib.getExe cfg.proton.outputs.wrapper;
          fhs.runScript = lib.getExe cfg.gamescope.outputs.wrapper;
          fhs.targetPkgs = p: cfg.proton.fhsTargetPkgs p ++ cfg.targetPkgs p;
          entrypoint = lib.getExe cfg.fhs.outputs.wrapper;
        })

        (lib.mkIf (cfg.runtime == "native") {
          # tmpfs /tmp/.X11-unix to own it as the sandbox user (host's is
          # root-owned, maps to nobody which blocks wlroots socket
          # creation). x11Binds ro-bind the actual host sockets on top.
          # Bind $STROM_GAMEDIR over $HOME so XDG saves persist in
          # ~/.strom/<game>/.
          bwrap.bind."$HOME" = "$STROM_GAMEDIR";
          bwrap.tmpfs = [ "/tmp/.X11-unix" ];
          bwrap.chmod."/tmp/.X11-unix" = "1777";
          bwrap.ro-bind-try = x11Binds;
          bwrap.env = cfg.env;

          # gamescope always wraps the inner command, so games configure
          # it via the typed `gamescope` sub-option rather than invoking
          # the binary themselves. If the game supplies a runScript it
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
          # Same bwrap shape as native (own /tmp/.X11-unix as the sandbox
          # user, ro-bind host X11 sockets, route $HOME at $STROM_GAMEDIR
          # so XDG saves persist), but route the launch through an FHS
          # chroot so old/native binaries that dlopen libs by bare name
          # (libudev, libwayland, bundled libSDL2, ...) find them via
          # /usr/lib.
          bwrap.bind."$HOME" = "$STROM_GAMEDIR";
          bwrap.tmpfs = [ "/tmp/.X11-unix" ];
          bwrap.chmod."/tmp/.X11-unix" = "1777";
          bwrap.ro-bind-try = x11Binds;
          bwrap.env = cfg.env;

          # gamescope always wraps the inner command, so games configure
          # it via the typed `gamescope` sub-option rather than invoking
          # the binary themselves. If the game supplies a runScript it
          # becomes the inner command (for env exports / mkdir / config
          # bootstrap before the real exec); otherwise gamescope wraps
          # the executable directly.
          gamescope.command =
            if cfg.runScript != null then
              "${pkgs.writeShellScript "${cfg.name}-runscript" cfg.runScript}"
            else
              overlayExe;
          fhs.runScript = lib.getExe cfg.gamescope.outputs.wrapper;
          fhs.targetPkgs = cfg.targetPkgs;
          entrypoint = lib.getExe cfg.fhs.outputs.wrapper;
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

  # Free-form meta passes around the wrapper-base meta schema (which only
  # accepts maintainers + platforms; games set description/mainProgram/...).
  gameMeta = gameSpec.meta or { };
  cleanedSpec = removeAttrs gameSpec [ "meta" ];

  configured = (wlib.wrapModule gameModule).apply cleanedSpec;
in
configured
