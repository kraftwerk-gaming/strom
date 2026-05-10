{
  lib,
  pkgs,
  wrappers,
  fetchIpfs,
}:

gameConfig:

let
  mod = lib.evalModules {
    modules = [
      gameModule
      { _module.args = { inherit pkgs wrappers fetchIpfs; }; }
      gameConfig
    ];
  };

  gameModule =
    {
      config,
      lib,
      pkgs,
      wrappers,
      fetchIpfs,
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

      # PS2 BIOS used by every pcsx2 runtime game. The .mec sidecar is
      # PCSX2's region/version cache; pre-generating it skips the first-
      # run BIOS scan dialog.
      ps2bios = fetchIpfs {
        cid = "QmRJTnELYzS3JsxzPcNiPXpQgzpG65W9JMjniwm5SQx1be";
        fallbackUrl = "https://archive.org/download/ps2-0100j-20000117/ps2-0200a-20040614.bin";
        hash = "sha256-bSPQAdryoPqLOBpdSfUXU8NuNiLQ8EvkavGgxUi+R0Q=";
        name = "ps2-0200a-20040614.bin";
      };

      ps2biosDir = pkgs.runCommandLocal "ps2-bios" { } ''
        mkdir -p $out
        cp ${ps2bios} $out/ps2-0200a-20040614.bin
        printf '\x03\x06\x02\x00' > $out/ps2-0200a-20040614.mec
      '';

      basePcsx2Ini = ''
        [UI]
        SettingsVersion = 1
        SetupWizardIncomplete = false
        StartFullscreen = false
        HideMouseCursor = true
        HideMainWindowWhenRunning = true

        [Folders]
        Bios = ${ps2biosDir}

        [EmuCore]
        EnableFastBoot = true
        EnableWideScreenPatches = true
        EnableGameFixes = true
        WarnAboutUnsafeSettings = false

        [EmuCore/GS]
        OsdShowMessages = false

        # Bind both SDL-0 and SDL-1 because SDL's controller enumeration can
        # put a real gamepad at index 1 when motion sensors or virtual
        # devices grab index 0. PCSX2 ORs the bindings, so whichever index
        # the actual controller ends up on works.
        [Pad1]
        Up = SDL-0/DPadUp & SDL-1/DPadUp
        Right = SDL-0/DPadRight & SDL-1/DPadRight
        Down = SDL-0/DPadDown & SDL-1/DPadDown
        Left = SDL-0/DPadLeft & SDL-1/DPadLeft
        Triangle = SDL-0/FaceNorth & SDL-1/FaceNorth
        Circle = SDL-0/FaceEast & SDL-1/FaceEast
        Cross = SDL-0/FaceSouth & SDL-1/FaceSouth
        Square = SDL-0/FaceWest & SDL-1/FaceWest
        Select = SDL-0/Back & SDL-1/Back
        Start = SDL-0/Start & SDL-1/Start
        L1 = SDL-0/LeftShoulder & SDL-1/LeftShoulder
        L2 = SDL-0/+LeftTrigger & SDL-1/+LeftTrigger
        R1 = SDL-0/RightShoulder & SDL-1/RightShoulder
        R2 = SDL-0/+RightTrigger & SDL-1/+RightTrigger
        L3 = SDL-0/LeftStick & SDL-1/LeftStick
        R3 = SDL-0/RightStick & SDL-1/RightStick
        Analog = SDL-0/Guide & SDL-1/Guide
        LUp = SDL-0/-LeftY & SDL-1/-LeftY
        LRight = SDL-0/+LeftX & SDL-1/+LeftX
        LDown = SDL-0/+LeftY & SDL-1/+LeftY
        LLeft = SDL-0/-LeftX & SDL-1/-LeftX
        RUp = SDL-0/-RightY & SDL-1/-RightY
        RRight = SDL-0/+RightX & SDL-1/+RightX
        RDown = SDL-0/+RightY & SDL-1/+RightY
        RLeft = SDL-0/-RightX & SDL-1/-RightX
        LargeMotor = SDL-0/LargeMotor & SDL-1/LargeMotor
        SmallMotor = SDL-0/SmallMotor & SDL-1/SmallMotor

        [EmuCore/Speedhacks]
        EECycleRate = 0
        EECycleSkip = 0
        fastCDVD = false
        IntcStat = true
        WaitLoop = true
        vuFlagHack = false
        vuThread = true
        vu1Instant = true

        [EmuCore/CPU/Recompiler]
        EnableEE = true
        EnableIOP = true
        EnableEECache = false
        EnableVU0 = true
        EnableVU1 = true
        vu0Overflow = true
        vu0ExtraOverflow = true
        vu0SignOverflow = true
        vu0Underflow = true
        vu1Overflow = true
        vu1ExtraOverflow = true
        vu1SignOverflow = true
        vu1Underflow = true
        fpuOverflow = true
        fpuExtraOverflow = true
        fpuFullMode = true

        [EmuCore/GS]
        upscale_multiplier = 2
        accurate_blending_unit = 1
        UserHacks_DisableRenderFixes = false
      '';

      pcsx2Ini = pkgs.writeText "PCSX2.ini" (basePcsx2Ini + cfg.pcsx2.extraIni);

      pcsx2LaunchCommand = ''
        mkdir -p "$STROM_GAMEDIR/config/PCSX2/inis" \
                 "$STROM_GAMEDIR/config/PCSX2/memcards" \
                 "$STROM_GAMEDIR/config/PCSX2/sstates" \
                 "$STROM_GAMEDIR/config/PCSX2/cache"
        # Always write config from nix (declarative); chmod so the user
        # can edit one-shot settings via the in-emulator UI without
        # being blocked by the read-only nix store source.
        cp ${pcsx2Ini} "$STROM_GAMEDIR/config/PCSX2/inis/PCSX2.ini"
        chmod 644 "$STROM_GAMEDIR/config/PCSX2/inis/PCSX2.ini"
        export XDG_CONFIG_HOME="$STROM_GAMEDIR/config"
        exec ${pkgs.pcsx2}/bin/pcsx2-qt \
          -batch \
          -fastboot \
          -- "${exePath}" ${exeArgs} "$@"
      '';

      # RetroArch core auto-pick: scan each provided core derivation for
      # *.so under lib/retroarch/cores/. If exactly one match across all
      # cores, use it. Caller can set retroarch.core explicitly to skip.
      retroarchCorePaths = lib.concatMap (
        core:
        map (f: "${core}/lib/retroarch/cores/${f}") (
          lib.filter (lib.hasSuffix ".so") (lib.attrNames (builtins.readDir "${core}/lib/retroarch/cores"))
        )
      ) cfg.retroarch.cores;

      retroarchCore =
        if cfg.retroarch.core != null then
          cfg.retroarch.core
        else if lib.length retroarchCorePaths == 1 then
          lib.head retroarchCorePaths
        else
          throw "${cfg.name}: retroarch.cores must contain exactly one core, or set retroarch.core explicitly";

      retroarchStaticCfg = pkgs.writeText "${cfg.name}-retroarch.cfg" (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: ''${k} = "${v}"'') (
            lib.filterAttrs (_: v: v != "") cfg.retroarch.settings
          )
        )
      );

      retroarchLaunchCommand = ''
        mkdir -p "$STROM_GAMEDIR/saves" "$STROM_GAMEDIR/states"
        # Compose the runtime cfg by prepending dynamic save/state paths
        # (which depend on $STROM_GAMEDIR) to the static settings file
        # baked into the nix store. retroarch reads the merged file via
        # --appendconfig.
        {
          echo "savefile_directory = \"$STROM_GAMEDIR/saves\""
          echo "savestate_directory = \"$STROM_GAMEDIR/states\""
          cat ${retroarchStaticCfg}
        } > "$STROM_CACHEDIR/retroarch.cfg"
        exec ${pkgs.retroarch}/bin/retroarch \
          -L ${retroarchCore} \
          --appendconfig "$STROM_CACHEDIR/retroarch.cfg" \
          "${exePath}" ${exeArgs} "$@"
      '';

      # Runs inside the sandbox (FHS chroot for proton/custom, plain
      # bwrap for native). Same script for every runtime; runtime-
      # specific blocks gate on cfg.runtime.
      innerWrapper = pkgs.writeShellScript "${cfg.name}-inner" ''
        set -euo pipefail

        export GAMEDIR="$STROM_OVERLAY"

        # Redirect shader caches into game-specific cache dir
        GAMECACHE="''${HOME:-.}/.cache/strom/${cfg.name}/shadercache"
        mkdir -p "$GAMECACHE"
        export MESA_SHADER_CACHE_DIR="$GAMECACHE"
        export DXVK_STATE_CACHE_PATH="$GAMECACHE"

        ${lib.optionalString (cfg.runtime == "proton") ''
          mkdir -p "$STROM_COMPATDATA/0"

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
          else if cfg.runtime == "retroarch" then
            retroarchLaunchCommand
          else if cfg.runtime == "pcsx2" then
            pcsx2LaunchCommand
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

      # Runs outside the sandbox: locks the game, kills orphans from prior
      # runs, mounts the overlay, then enters the sandbox (FHS chroot for
      # proton/custom, plain bwrap for native). Uses PR_SET_CHILD_SUBREAPER
      # so orphaned wine processes get reparented to this wrapper instead of
      # init. gamescopereaper escapes the subreaper (separate session) and
      # winedevice.exe escapes too, so cleanup walks /proc to catch anything
      # tagged with our compatdata/overlay path in cmdline or environ.
      outerWrapper =
        sandbox:
        pkgs.writeShellScript "${cfg.name}-wrapper" ''
          # Re-exec under subreaper if not already
          if [ -z "''${STROM_SUBREAPER-}" ]; then
            export STROM_SUBREAPER=1
            exec ${subreaper}/bin/subreaper "$0" "$@"
          fi

          GAMEDIR="''${HOME:-.}/.strom/${cfg.name}"
          export STROM_GAMEDIR="$GAMEDIR"
          # STROM_COMPATDATA is exported (and the dir created) for every
          # runtime: sandboxBwrapArgs binds it via `--bind`, which fails
          # if the path doesn't exist. Non-proton runtimes never write
          # anything into it. Exporting it also keeps the proc-walk
          # `grep -F -e "$STROM_COMPATDATA/"` from matching an empty
          # string against every process's cmdline.
          export STROM_COMPATDATA="''${HOME:-.}/.strom/.compatdata/${cfg.name}"
          export STROM_CACHEDIR="''${HOME:-.}/.cache/strom/${cfg.name}"
          mkdir -p "$GAMEDIR" "$STROM_COMPATDATA" "$STROM_CACHEDIR"
          ${lib.optionalString (cfg.runtime == "proton") ''
            mkdir -p \
              "''${HOME:-.}/.cache/umu" \
              "''${HOME:-.}/.cache/umu-protonfixes" \
              "''${HOME:-.}/.cache/wine"
          ''}

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
            # version files match. Detect a broken symlink under pfx/drive_c
            # whose target points into /nix/store (the proton symlink-pfx
            # signature) and wipe the compatdata so proton re-bootstraps
            # against the current store path. Restricting to /nix/store
            # targets keeps user-introduced broken symlinks (mod tooling,
            # custom configs, manual experiments) from triggering a wipe.
            # Game saves live in $STROM_GAMEDIR (~/.strom/<game>), not the
            # wineprefix, so user progress survives the wipe either way.
            if [ -d "$STROM_COMPATDATA/0/pfx/drive_c" ]; then
              stale_link=$(find "$STROM_COMPATDATA/0/pfx/drive_c" \
                -xtype l -lname '/nix/store/*' -print -quit 2>/dev/null)
              if [ -n "$stale_link" ]; then
                echo "${cfg.name}: wiping wineprefix with stale /nix/store symlink ($stale_link)" >&2
                rm -rf "$STROM_COMPATDATA/0"
              fi
            fi
          ''}

          export STROM_OVERLAY=$(${prepareGameDir} "$GAMEDIR")

          cleanup() {
            kill -KILL -- -$SANDBOX_PID 2>/dev/null || true
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
          setsid ${sandbox}/bin/${cfg.name}-sandbox "$@" &
          SANDBOX_PID=$!
          wait $SANDBOX_PID 2>/dev/null
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
            "retroarch"
            "pcsx2"
          ];
          default = "custom";
          description = "Runtime environment type";
        };

        proton = mkOption {
          type = types.attrs;
          default = { };
          description = "Configuration passed to the proton wrapperModule.";
        };

        retroarch = mkOption {
          type = types.submodule {
            options = {
              cores = mkOption {
                type = types.listOf types.package;
                default = [ ];
                description = "Libretro core derivations to bind to retroarch.";
              };
              core = mkOption {
                type = types.nullOr types.path;
                default = null;
                defaultText = lib.literalMD "Auto-picked when `cores` contains exactly one core.";
                description = "Path to the libretro core .so to load. Override when `cores` ships multiple.";
              };
              settings = mkOption {
                type = types.submodule {
                  freeformType = types.attrsOf types.str;
                  options = {
                    input_autodetect_enable = mkOption {
                      type = types.str;
                      default = "true";
                    };
                    input_joypad_driver = mkOption {
                      type = types.str;
                      default = "sdl2";
                    };
                    pause_nonactive = mkOption {
                      type = types.str;
                      default = "false";
                    };
                    video_driver = mkOption {
                      type = types.str;
                      default = "vulkan";
                    };
                    video_fullscreen = mkOption {
                      type = types.str;
                      default = "false";
                    };
                    video_windowed_fullscreen = mkOption {
                      type = types.str;
                      default = "false";
                    };
                  };
                };
                default = { };
                description = "RetroArch settings written into retroarch.cfg.";
              };
            };
          };
          default = { };
          description = "RetroArch configuration when runtime = retroarch.";
        };

        pcsx2 = mkOption {
          type = types.submodule {
            options = {
              extraIni = mkOption {
                type = types.str;
                default = "";
                description = "INI fragments appended after the shared base config.";
              };
            };
          };
          default = { };
          description = "PCSX2 configuration when runtime = pcsx2.";
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
          default = [ cfg.src ] ++ lib.optionals (cfg.runtime == "pcsx2") [ ps2bios ];
          defaultText = lib.literalMD "`[ src ]` plus the shared PS2 BIOS for `runtime = pcsx2`.";
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
                  if [ -d "$src" ]; then
                    cp -r "$src"/. $out/
                  else
                    # Flat file (typical for fetchIpfs roms / isos): place
                    # under $out with the original name (no nix store hash
                    # prefix), so the inner wrapper can refer to it as
                    # $GAMEDIR/${cfg.src.name}.
                    cp "$src" "$out/${cfg.src.name or "src"}"
                  fi
                ''
            );

        _build =
          let
            # Baseline 32-bit + 64-bit graphics/audio stack proton games
            # need inside the FHS chroot. cfg.targetPkgs is appended on
            # top for game-specific deps.
            protonFhsPkgs = p: [
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
            ];

            # Native runtime keeps the host filesystem visible
            # (--ro-bind / /) so libraries the game brings via
            # LD_LIBRARY_PATH resolve against the host's nix store.
            # Proton/custom go through buildFHSEnv which chroots into a
            # synthetic /usr — incompatible with native binaries that
            # reference store paths directly.
            nativeSandbox = pkgs.writeShellApplication {
              name = "${cfg.name}-sandbox";
              runtimeInputs = [ pkgs.bubblewrap ];
              text = ''
                # Always tmpfs /tmp/.X11-unix so it is owned by us inside the userns.
                # Host /tmp/.X11-unix is owned by root, which maps to nobody in the
                # sandbox, causing wlroots/Xwayland to refuse socket creation on Wayland.
                x11_args=(--tmpfs /tmp/.X11-unix --chmod 1777 /tmp/.X11-unix)
                if [[ "''${DISPLAY-}" == *:* ]]; then
                  display_nr=''${DISPLAY/#*:}
                  display_nr=''${display_nr/%.*}
                  x11_args+=(--ro-bind-try "/tmp/.X11-unix/X$display_nr" "/tmp/.X11-unix/X$display_nr")
                fi

                # Bind $STROM_GAMEDIR over $HOME so XDG-style saves
                # (e.g. $HOME/.local/share/<game>, $HOME/.config/<game>)
                # land in ~/.strom/<game>/ and persist. The previous
                # --tmpfs ''${HOME} setup discarded any save the game
                # wrote outside the overlay (which is most native Linux
                # games). $STROM_GAMEDIR is also kept self-bound so
                # absolute references in preRun / runScript resolve.
                exec bwrap \
                  --ro-bind / / \
                  --dev-bind /dev /dev \
                  --proc /proc \
                  --bind /tmp /tmp \
                  "''${x11_args[@]}" \
                  --bind /run /run \
                  --bind "$STROM_GAMEDIR" "''${HOME}" \
                  --bind "$STROM_GAMEDIR" "$STROM_GAMEDIR" \
                  --bind "$STROM_CACHEDIR" "$STROM_CACHEDIR" \
                  ${innerWrapper} "$@"
              '';
            };

            fhsSandbox = pkgs.buildFHSEnv {
              name = "${cfg.name}-sandbox";
              runScript = innerWrapper;
              targetPkgs = p: lib.optionals (cfg.runtime == "proton") (protonFhsPkgs p) ++ cfg.targetPkgs p;
              extraBwrapArgs =
                lib.optionals (cfg.runtime == "proton") [
                  "--ro-bind /sys /sys"
                  "--bind /run /run"
                ]
                ++ sandboxBwrapArgs
                ++ cfg.extraBwrapArgs;
            };

            # native, retroarch, and pcsx2 all run nix-built linux binaries
            # against the host filesystem. They use the plain bwrap sandbox
            # so /nix/store closures resolve directly. Proton / custom go
            # through the FHS chroot so /usr/lib lookups satisfy Wine and
            # game-supplied native helpers.
            sandbox =
              if
                builtins.elem cfg.runtime [
                  "native"
                  "retroarch"
                  "pcsx2"
                ]
              then
                nativeSandbox
              else
                fhsSandbox;
          in
          pkgs.stdenvNoCC.mkDerivation {
            pname = cfg.name;
            version = "0";
            dontUnpack = true;
            installPhase = ''
              mkdir -p $out/bin
              ln -s ${outerWrapper sandbox} $out/bin/${cfg.name}
            '';
            inherit (cfg) meta;
            passthru = {
              inherit (cfg) runtime ipfsSources;
            };
          };
      };
    };
in
mod.config._build
