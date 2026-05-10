{
  lib,
  pkgs,
  wrappers,
}:

gameConfig:

let
  mod = lib.evalModules {
    modules = [
      gameModule
      { _module.args = { inherit pkgs wrappers; }; }
      gameConfig
    ];
  };

  gameModule =
    {
      config,
      lib,
      pkgs,
      wrappers,
      ...
    }:

    let
      cfg = config;

      wlib = wrappers.lib;

      gamescopeModule = import ./gamescope.nix { inherit wlib; };
      protonModule = import ./proton.nix { inherit wlib; };
      fuseOverlayfsModule = import ./fuse-overlayfs.nix { inherit wlib; };

      # Resolve executable: absolute paths used as-is, relative paths prefixed with $GAMEDIR
      exePath = if lib.hasPrefix "/" cfg.executable then cfg.executable else "$GAMEDIR/${cfg.executable}";

      # Configured gamescope wrapper (used by proton and native runtimes)
      gamescopeConfig = gamescopeModule.apply ({ inherit pkgs; } // cfg.gamescope);

      # Configured proton wrapper
      protonConfig = protonModule.apply (
        {
          inherit pkgs;
          compatDataPath = "\${HOME:-.}/.strom/.compatdata/${cfg.name}/0";
        }
        // cfg.proton
      );

      # Configured fuse-overlayfs wrapper for game data overlay
      prepareGameDirConfig = fuseOverlayfsModule.apply {
        inherit pkgs;
        gameFiles = cfg._gameData;
        copyGlobs = cfg.copyGlobs;
      };

      prepareGameDir = lib.getExe prepareGameDirConfig.wrapper;

      # Sandbox: tmpfs HOME, only game-specific dirs are accessible.
      sandboxBwrapArgs = [
        "--tmpfs \${HOME}"
        "--bind \${STROM_GAMEDIR} \${STROM_GAMEDIR}"
        "--bind \${STROM_COMPATDATA} \${STROM_COMPATDATA}"
        "--bind \${STROM_CACHEDIR} \${STROM_CACHEDIR}"
        "--bind-try \${HOME}/.cache/umu \${HOME}/.cache/umu"
        "--bind-try \${HOME}/.cache/umu-protonfixes \${HOME}/.cache/umu-protonfixes"
        "--bind-try \${HOME}/.cache/wine \${HOME}/.cache/wine"
        "--ro-bind-try \${HOME}/.local/share/vulkan \${HOME}/.local/share/vulkan"
        "--chdir /"
      ];

      # The launch command for proton runtime (when no runScript)
      exeArgs = lib.concatStringsSep " " (map lib.escapeShellArg cfg.executableArgs);

      protonLaunchCommand = ''
        # shellcheck disable=SC2086
        exec ${lib.getExe gamescopeConfig.wrapper} ''${GAMESCOPE_PARAMS:-} -- ${lib.getExe protonConfig.wrapper} "${exePath}" ${exeArgs} "$@"
      '';

      # The launch command for native runtime (when no runScript)
      nativeLaunchCommand = ''
        # shellcheck disable=SC2086
        exec ${lib.getExe gamescopeConfig.wrapper} ''${GAMESCOPE_PARAMS:-} -- "${exePath}" ${exeArgs} "$@"
      '';

      # Runs inside FHS/bwrap
      innerWrapper = pkgs.writeShellScript "${cfg.name}-inner" ''
        set -euo pipefail

        export GAMEDIR="$STROM_OVERLAY"
        COMPATDATA="''${HOME:-.}/.strom/.compatdata/${cfg.name}/0"
        mkdir -p "$COMPATDATA"

        # Redirect shader caches into game-specific cache dir
        GAMECACHE="''${HOME:-.}/.cache/strom/${cfg.name}/shadercache"
        mkdir -p "$GAMECACHE"
        export MESA_SHADER_CACHE_DIR="$GAMECACHE"
        export DXVK_STATE_CACHE_PATH="$GAMECACHE"

        ${lib.optionalString (cfg.runtime == "proton") ''
          # Export PROTON_RUN for games with custom runScripts
          export PROTON_RUN="${lib.getExe protonConfig.wrapper}"

          # Baseline env shared by every Proton game. cfg.env exports below
          # come after, so per-game overrides (e.g. SteamAppId for games
          # whose Steamworks init demands the real ID) win.
          export SteamAppId="0"
          export SteamGameId="0"
          # Real env knob honoured by protonfixes/__init__.py:check_conditions().
          # Disables protonfixes' winetricks shellouts (vcrun, dotnet, dxvk
          # verbs) which are forbidden in this project. The cargo-culted
          # PROTON_NO_GAME_FIXES name does not exist anywhere in protonfixes.
          export PROTONFIXES_DISABLE="1"
          export DXVK_ASYNC="1"
          # 32-bit + 64-bit FHS lib dirs so Proton's loader finds both arches.
          export LD_LIBRARY_PATH="/usr/lib32:/usr/lib:/usr/lib64"
        ''}

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") cfg.env
        )}

        cd "$GAMEDIR"
        ${lib.optionalString (cfg.runtime == "proton" && cfg.saveLocations != [ ]) ''
          # Relocate game save / config paths out of the wineprefix into
          # $STROM_GAMEDIR. The wineprefix is treated as disposable (the
          # auto-wipe path nukes it on stale-store-path detection, and a
          # user can `rm -rf ~/.strom/.compatdata/<game>` at any time);
          # anything under drive_c/users/steamuser that the game writes
          # has to be symlinked out so a wipe doesn't take saves with it.
          for __strom_save in ${lib.escapeShellArgs cfg.saveLocations}; do
            __strom_src="$STROM_COMPATDATA/0/pfx/drive_c/users/steamuser/$__strom_save"
            __strom_dst="$STROM_GAMEDIR/$(basename "$__strom_save")"
            mkdir -p "$__strom_dst"
            if [ -d "$__strom_src" ] && [ ! -L "$__strom_src" ]; then
              # First-run-after-wipe (or first-ever migration): pull any
              # existing in-prefix data into $STROM_GAMEDIR before we
              # replace the in-prefix path with a symlink.
              cp -an "$__strom_src/." "$__strom_dst/" 2>/dev/null || true
              rm -rf "$__strom_src"
            fi
            mkdir -p "$(dirname "$__strom_src")"
            ln -snf "$__strom_dst" "$__strom_src"
          done
        ''}
        ${cfg.preRun}
        ${
          if cfg.runScript != null then
            cfg.runScript
          else if cfg.runtime == "proton" then
            protonLaunchCommand
          else if cfg.executable != "" then
            nativeLaunchCommand
          else
            ''
              echo "No runScript or executable specified" >&2
              exit 1
            ''
        }
      '';

      subreaper = pkgs.callPackage ../pkgs/subreaper.nix { };

      # Runs outside bwrap: locks the game, kills orphans from prior runs,
      # mounts the overlay, then enters the FHS env. Uses PR_SET_CHILD_SUBREAPER
      # so orphaned wine processes get reparented to this wrapper instead of
      # init. gamescopereaper escapes the subreaper (separate session) and
      # winedevice.exe escapes too, so cleanup walks /proc to catch anything
      # tagged with our compatdata/overlay path in cmdline or environ.
      outerWrapper =
        fhsEnv:
        pkgs.writeShellScript "${cfg.name}-wrapper" ''
          # Re-exec under subreaper if not already
          if [ -z "''${STROM_SUBREAPER-}" ]; then
            export STROM_SUBREAPER=1
            exec ${subreaper}/bin/subreaper "$0" "$@"
          fi

          GAMEDIR="''${HOME:-.}/.strom/${cfg.name}"
          export STROM_GAMEDIR="$GAMEDIR"
          export STROM_COMPATDATA="''${HOME:-.}/.strom/.compatdata/${cfg.name}"
          export STROM_CACHEDIR="''${HOME:-.}/.cache/strom/${cfg.name}"
          mkdir -p "$GAMEDIR" "$STROM_COMPATDATA" "$STROM_CACHEDIR" \
            "''${HOME:-.}/.cache/umu" "''${HOME:-.}/.cache/umu-protonfixes" "''${HOME:-.}/.cache/wine"

          # Walk /proc and SIGKILL any process whose cmdline or environ
          # references one of the markers — catches gamescopereaper (cmdline
          # has the overlay path), winedevice.exe (WINEPREFIX in environ),
          # and wine64 helpers spawned by Proton's prefix init. Trailing
          # slashes anchor the match so e.g. "fallout/" never matches
          # "fallout-2/", and -F treats the markers as fixed strings so
          # regex metachars in paths don't bite.
          strom_match_proc() {
            grep -qaF -e "$STROM_COMPATDATA/" -e "$STROM_CACHEDIR/overlay/" \
              "/proc/$1/cmdline" "/proc/$1/environ" 2>/dev/null
          }
          strom_kill_marked() {
            local pid
            for pid in /proc/[0-9]*; do
              pid="''${pid#/proc/}"
              [ "$pid" = "$$" ] && continue
              if strom_match_proc "$pid"; then
                kill -KILL "$pid" 2>/dev/null
              fi
            done
          }
          strom_any_marked() {
            local pid
            for pid in /proc/[0-9]*; do
              pid="''${pid#/proc/}"
              [ "$pid" = "$$" ] && continue
              strom_match_proc "$pid" && return 0
            done
            return 1
          }

          # Single-instance lock per game so two launches can't clobber the
          # same wineprefix.
          exec 9>"$STROM_CACHEDIR/.lock"
          if ! flock -n 9; then
            echo "${cfg.name}: another instance is already running" >&2
            echo "if no instance is running, remove the stale lock:" >&2
            echo "  rm $STROM_CACHEDIR/.lock" >&2
            exit 1
          fi

          # Preflight: nuke leftover wine/gamescope/proton processes from
          # crashed prior runs, then unmount any stale overlay.
          strom_kill_marked
          for _ in 1 2 3 4 5; do
            strom_any_marked || break
            sleep 0.2
          done
          if mountpoint -q "$STROM_CACHEDIR/overlay" 2>/dev/null; then
            fusermount -uz "$STROM_CACHEDIR/overlay" 2>/dev/null || true
          fi

          ${lib.optionalString (cfg.runtime == "proton") ''
            # pkgs/proton-symlink-pfx.patch makes proton symlink default_pfx
            # DLLs into the wineprefix instead of copying them — saves ~600 MB
            # per prefix but bakes the proton store path into every symlink.
            # When nix-collect-garbage removes an old proton between releases,
            # those symlinks become broken and games die at loader_init with
            # c0000135 (typically DDRAW.dll → wined3d.dll → libvkd3d-1.dll).
            # Proton's incremental prefix update doesn't catch this because
            # version files match. Detect any broken symlink under
            # pfx/drive_c/ and wipe the compatdata so proton re-bootstraps
            # against the current store path. Game saves live in
            # $STROM_GAMEDIR (~/.strom/<game>), not the wineprefix, so user
            # progress survives.
            if [ -d "$STROM_COMPATDATA/0/pfx/drive_c" ] && \
               find "$STROM_COMPATDATA/0/pfx/drive_c" -xtype l -print -quit 2>/dev/null \
                 | read -r _; then
              echo "${cfg.name}: wiping wineprefix with broken symlinks (stale proton store path)" >&2
              rm -rf "$STROM_COMPATDATA/0"
            fi
          ''}

          export STROM_OVERLAY=$(${prepareGameDir} "$GAMEDIR")

          cleanup() {
            kill -KILL -- -$FHS_PID 2>/dev/null
            local pids
            pids=$(ps -o pid= --ppid $$ 2>/dev/null) || true
            [ -n "$pids" ] && kill -KILL $pids 2>/dev/null
            strom_kill_marked
            wait 2>/dev/null
            fusermount -uz "$STROM_OVERLAY" 2>/dev/null
          }
          trap cleanup EXIT INT TERM

          # Run in new process group so kill -9 0 inside bwrap
          # doesn't kill this wrapper before cleanup runs
          setsid ${fhsEnv}/bin/${cfg.name}-fhs "$@" &
          FHS_PID=$!
          wait $FHS_PID 2>/dev/null
        '';
    in
    {
      options = with lib; {
        name = mkOption {
          type = types.str;
          description = "Game name (used for ~/.strom/<name>)";
        };

        src = mkOption {
          type = types.package;
          description = "Source archive/fetchurl";
        };

        buildScript = mkOption {
          type = types.str;
          default = "";
          description = "Shell script to extract/prepare game data. Runs in nix build. Has $src and $out.";
        };

        nativeBuildInputs = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = "Build-time dependencies for buildScript";
        };

        executable = mkOption {
          type = types.str;
          default = "";
          description = "Game executable path, relative to GAMEDIR or absolute (for proton/native runtime)";
        };

        executableArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Arguments passed to the game executable.";
        };

        gamescope = mkOption {
          type = types.attrs;
          default = { };
          description = "Configuration passed to the gamescope wrapperModule.";
        };

        preRun = mkOption {
          type = types.str;
          default = "";
          description = "Shell commands to run before launching the game (inside FHS, has $GAMEDIR)";
        };

        saveLocations = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Paths under the wineprefix's drive_c/users/steamuser/ where the
            game writes saves, profiles, or persistent configs. The launcher
            symlinks each one into $STROM_GAMEDIR before the game starts so
            user data survives prefix wipes (auto-wipe on stale Proton store
            paths after GC, or manual reset). Only used when runtime = "proton".
            Example: [ "AppData/Roaming/Ubisoft/Anno1404Addon" "Documents/Anno1404" ]
          '';
        };

        runScript = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Custom run script. Overrides the default launch command if set.";
        };

        copyGlobs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Glob patterns for files/dirs to copy instead of symlink. Trailing / for dirs.";
        };

        env = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Environment variables to set before launching";
        };

        runtime = mkOption {
          type = types.enum [
            "proton"
            "native"
            "custom"
          ];
          default = "custom";
          description = "Runtime environment type";
        };

        proton = mkOption {
          type = types.attrs;
          default = { };
          description = "Configuration passed to the proton wrapperModule.";
        };

        targetPkgs = mkOption {
          type = types.functionTo (types.listOf types.package);
          default = _: [ ];
          description = "FHS environment packages (for buildFHSEnv)";
        };

        extraBwrapArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Extra bwrap arguments for FHS environment";
        };

        ipfsSources = mkOption {
          type = types.listOf types.package;
          default = [ cfg.src ];
          description = "List of fetchIpfs derivations whose CIDs should be pinned.";
        };

        meta = mkOption {
          type = types.attrs;
          default = { };
          description = "Derivation metadata";
        };

        # Internal options
        _gameData = mkOption {
          type = types.package;
          internal = true;
          readOnly = true;
        };
        _build = mkOption {
          type = types.package;
          internal = true;
          readOnly = true;
        };
      };

      config = {
        _gameData =
          pkgs.runCommandLocal "${cfg.name}-data"
            {
              nativeBuildInputs = cfg.nativeBuildInputs;
              src = cfg.src;
            }
            (
              if cfg.buildScript != "" then
                cfg.buildScript
              else
                ''
                  mkdir -p $out
                  cp -r $src/. $out/ || cp $src $out/
                ''
            );

        _build =
          if cfg.runtime == "proton" then
            let
              fhsEnv = pkgs.buildFHSEnv {
                name = "${cfg.name}-fhs";
                runScript = innerWrapper;
                targetPkgs =
                  p:
                  [
                    p.freetype
                    p.glibc
                    p.gamescope
                    p.python3
                    p.mesa
                    p.vulkan-loader
                    p.libGL
                    p.libx11
                    p.libxext
                    p.libxcb
                    p.libxcursor
                    p.libxrandr
                    p.libxi
                    p.libxfixes
                    p.libxrender
                    p.libxcomposite
                    p.libxinerama
                    p.libxxf86vm
                    p.alsa-lib
                    p.libpulseaudio
                    p.openal
                    p.systemd
                    (pkgs.callPackage ../pkgs/sdl2.nix { })
                    p.pkgsi686Linux.freetype
                    p.pkgsi686Linux.glibc
                    p.pkgsi686Linux.glib
                    p.pkgsi686Linux.libx11
                    p.pkgsi686Linux.libxext
                    p.pkgsi686Linux.libxcb
                    p.pkgsi686Linux.libxcursor
                    p.pkgsi686Linux.libxrandr
                    p.pkgsi686Linux.libxi
                    p.pkgsi686Linux.libxfixes
                    p.pkgsi686Linux.libxrender
                    p.pkgsi686Linux.libxcomposite
                    p.pkgsi686Linux.libxinerama
                    p.pkgsi686Linux.libxxf86vm
                    p.pkgsi686Linux.libGL
                    p.pkgsi686Linux.mesa
                    p.pkgsi686Linux.vulkan-loader
                    p.pkgsi686Linux.openal
                    p.pkgsi686Linux.alsa-lib
                    p.pkgsi686Linux.libpulseaudio
                  ]
                  ++ (cfg.targetPkgs p);
                extraBwrapArgs = [
                  "--ro-bind /sys /sys"
                  "--bind /run /run"
                ]
                ++ sandboxBwrapArgs
                ++ cfg.extraBwrapArgs;
              };
            in
            pkgs.stdenvNoCC.mkDerivation {
              pname = cfg.name;
              version = "0";
              dontUnpack = true;
              installPhase = ''
                mkdir -p $out/bin
                ln -s ${outerWrapper fhsEnv} $out/bin/${cfg.name}
              '';
              inherit (cfg) meta;
              passthru = {
                runtime = cfg.runtime;
                inherit (cfg) ipfsSources;
              };
            }
          else if cfg.runtime == "native" then
            let
              nativeInner = pkgs.writeShellScript "${cfg.name}-inner" ''
                set -euo pipefail
                export GAMEDIR="$STROM_OVERLAY"
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") cfg.env
                )}
                cd "$GAMEDIR"
                ${cfg.preRun}
                ${
                  if cfg.runScript != null then
                    cfg.runScript
                  else if cfg.executable != "" then
                    nativeLaunchCommand
                  else
                    ''
                      echo "No runScript or executable specified" >&2
                      exit 1
                    ''
                }
              '';

            in
            (pkgs.writeShellApplication {
              inherit (cfg) name meta;
              runtimeInputs = [ pkgs.bubblewrap ];
              text = ''
                # Re-exec under subreaper if not already
                if [ -z "''${STROM_SUBREAPER-}" ]; then
                  export STROM_SUBREAPER=1
                  exec ${subreaper}/bin/subreaper "$0" "$@"
                fi

                USERDIR="''${HOME:-.}/.strom/${cfg.name}"
                mkdir -p "$USERDIR"
                export STROM_GAMEDIR="$USERDIR"
                export STROM_CACHEDIR="''${HOME:-.}/.cache/strom/${cfg.name}"
                mkdir -p "$STROM_CACHEDIR"
                export STROM_OVERLAY
                STROM_OVERLAY=$(${prepareGameDir} "$USERDIR")

                cleanup() {
                  kill -KILL -- -"$INNER_PID" 2>/dev/null || true
                  # Kill reparented orphans (processes that became our children
                  # via PR_SET_CHILD_SUBREAPER). One pass, no loop.
                  local pids
                  pids=$(ps -o pid= --ppid $$ 2>/dev/null) || true
                  [ -n "$pids" ] && kill -KILL "$pids" 2>/dev/null || true
                  wait 2>/dev/null || true
                  fusermount -uz "$STROM_OVERLAY" 2>/dev/null || true
                }
                trap cleanup EXIT INT TERM

                # Always tmpfs /tmp/.X11-unix so it is owned by us inside the userns.
                # Host /tmp/.X11-unix is owned by root, which maps to nobody in the
                # sandbox, causing wlroots/Xwayland to refuse socket creation on Wayland.
                x11_args=(--tmpfs /tmp/.X11-unix --chmod 1777 /tmp/.X11-unix)
                if [[ "''${DISPLAY-}" == *:* ]]; then
                  display_nr=''${DISPLAY/#*:}
                  display_nr=''${display_nr/%.*}
                  x11_args+=(--ro-bind-try "/tmp/.X11-unix/X$display_nr" "/tmp/.X11-unix/X$display_nr")
                fi

                setsid bwrap \
                  --ro-bind / / \
                  --dev-bind /dev /dev \
                  --proc /proc \
                  --bind /tmp /tmp \
                  "''${x11_args[@]}" \
                  --bind /run /run \
                  --tmpfs "''${HOME}" \
                  --bind "$STROM_GAMEDIR" "$STROM_GAMEDIR" \
                  --bind "$STROM_CACHEDIR" "$STROM_CACHEDIR" \
                  ${nativeInner} "$@" &
                INNER_PID=$!
                wait $INNER_PID 2>/dev/null || true
              '';
            }).overrideAttrs
              (_: {
                passthru = {
                  runtime = cfg.runtime;
                  inherit (cfg) ipfsSources;
                };
              })
          else
            # custom: FHS env with overlay mounted outside
            let
              customFhs = pkgs.buildFHSEnv {
                name = "${cfg.name}-fhs";
                runScript = innerWrapper;
                targetPkgs = cfg.targetPkgs;
                extraBwrapArgs = sandboxBwrapArgs ++ cfg.extraBwrapArgs;
              };
            in
            pkgs.stdenvNoCC.mkDerivation {
              pname = cfg.name;
              version = "0";
              dontUnpack = true;
              installPhase = ''
                mkdir -p $out/bin
                ln -s ${outerWrapper customFhs} $out/bin/${cfg.name}
              '';
              inherit (cfg) meta;
              passthru = {
                runtime = cfg.runtime;
                inherit (cfg) ipfsSources;
              };
            };
      };
    };
in
mod.config._build
