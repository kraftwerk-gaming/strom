# Proton wrapperModule (raw module source).
#
# Runs `proton waitforexitandrun <exe>` inside the wrapper. Takes
# ownership of all proton-specific concerns: the steamclient stub,
# saveLocations relocation, wineprefix auto-wipe, baseline env (PROTONFIXES,
# SteamAppId, ...), and graceful wineserver shutdown.
#
# Sits inside the FHS chroot (the wrapper bash runs after FHS-bwrap has
# entered the synthetic /usr). preHook therefore sees both the host-bound
# $STROM_COMPATDATA / $STROM_GAMEDIR paths and the /usr/lib stack.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  stub = config.pkgs.callPackage ../pkgs/steamclient-stub { };
  shellEscape = arg: ''"${arg}"'';
in
{
  _class = "wrapper";

  options = {
    exe = mkOption {
      type = types.either types.path types.str;
      description = "Path to the Windows .exe to run via proton waitforexitandrun.";
    };

    compatDataPath = mkOption {
      type = types.str;
      description = "Path for Proton compatibility data. May contain shell variables.";
    };

    saveLocations = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Paths under drive_c/users/steamuser/ where the game writes saves.
        Each is symlinked into $STROM_GAMEDIR so saves survive wineprefix
        wipes. preHook performs the migration + symlinking.
      '';
    };

    autoWipePrefix = mkOption {
      type = types.bool;
      default = true;
      description = ''
        On launch, if drive_c contains a broken /nix/store symlink (signature
        of GC'd default_pfx after a proton bump), wipe $compatDataPath so
        proton re-bootstraps. saveLocations live outside the prefix and
        survive.
      '';
    };

    fhsTargetPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = p: [
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
        (config.pkgs.callPackage ../pkgs/sdl2.nix { })
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
      description = ''
        Function (p: [packages]) returning the 32+64-bit graphics / audio
        stack proton needs inside an FHS chroot. Consumers (e.g. mkGame)
        wire this into the surrounding fhsUserEnv wrapper's targetPkgs;
        reading `config.proton.fhsTargetPkgs` lets them merge in their
        own per-game extras on top of the baseline.
      '';
    };
  };

  config = {
    package = config.pkgs.callPackage ../pkgs/proton.nix { };
    exePath = "${config.package}/proton";
    binName = lib.mkDefault "proton-wrapper";

    extraPackages = [ config.pkgs.python3 ];

    # All defaults — games can override via cfg.env in mkGame.
    env = {
      STEAM_COMPAT_DATA_PATH = lib.mkDefault config.compatDataPath;
      STEAM_COMPAT_CLIENT_INSTALL_PATH = lib.mkDefault config.compatDataPath;
      STEAM_COMPAT_APP_ID = lib.mkDefault "0";
      SteamAppId = lib.mkDefault "0";
      SteamGameId = lib.mkDefault "0";
      PROTONFIXES_DISABLE = lib.mkDefault "1";
      DXVK_ASYNC = lib.mkDefault "1";
      # Bluetooth Xbox controllers via xpadneo expose a /dev/hidraw with
      # the wired Xbox 360 VID/PID (045e:028e) but speak BLE HoG. SDL's
      # Xbox 360 HIDAPI subdriver latches onto the hidraw, tries to
      # drive it as a wired pad, and the game sees a dead controller
      # while xpadneo's evdev (where state actually flows) is ignored.
      # Only kill the Xbox 360 path so Switch/PS HIDAPI drivers — which
      # provide correct button maps + rumble/gyro for those pads — stay
      # active. Set to "1" per-game via cfg.env if a wired-360 game
      # needs the HIDAPI driver instead of evdev.
      SDL_JOYSTICK_HIDAPI_XBOX_360 = lib.mkDefault "0";
      # 32-bit + 64-bit FHS lib dirs so Proton's loader finds both arches.
      LD_LIBRARY_PATH = lib.mkDefault "/usr/lib32:/usr/lib:/usr/lib64";
      # GE-Proton 10 ships an accessibility helper (xalia.exe) that
      # attaches to the game process to bridge the wine a11y stack to
      # at-spi. On freshly-bootstrapped prefixes (no at-spi bus in our
      # bwrap) xalia spins waiting to connect and games like hl.exe
      # deadlock waiting for the a11y handshake — single thread stuck
      # in futex_wait_multiple. We don't need accessibility; opt out.
      PROTON_DISABLE_XALIA = lib.mkDefault "1";
    };

    args = lib.mkOrder 100 [
      "waitforexitandrun"
      config.exe
    ];

    preHook = ''
      mkdir -p "${config.compatDataPath}"

      ${lib.optionalString config.autoWipePrefix ''
        # Wineprefix auto-wipe: pkgs/proton-symlink-pfx.patch makes proton
        # symlink default_pfx DLLs from /nix/store into the wineprefix.
        # When GC removes an old proton, those symlinks dangle and games
        # die at loader_init. Detect a broken /nix/store symlink under
        # drive_c and wipe the compatdata so proton re-bootstraps.
        if [ -d "${config.compatDataPath}/pfx/drive_c" ]; then
          stale_link=$(find "${config.compatDataPath}/pfx/drive_c" \
            -xtype l -lname '/nix/store/*' -print -quit 2>/dev/null)
          if [ -n "$stale_link" ]; then
            echo "proton: wiping wineprefix with stale /nix/store symlink ($stale_link)" >&2
            rm -rf "${config.compatDataPath}"
            mkdir -p "${config.compatDataPath}"
          fi
        fi
      ''}

      # Steamclient stub: lsteamclient hardcodes $HOME/.steam/sdk{32,64}/
      # steamclient.so and asserts on dlopen failure. The stub satisfies
      # it without requiring a host Steam install.
      mkdir -p "''${HOME:-.}/.steam/sdk32" "''${HOME:-.}/.steam/sdk64"
      ln -sf ${stub}/sdk32/steamclient.so "''${HOME:-.}/.steam/sdk32/steamclient.so"
      ln -sf ${stub}/sdk64/steamclient.so "''${HOME:-.}/.steam/sdk64/steamclient.so"

      ${lib.optionalString (config.saveLocations != [ ]) ''
        # Save-symlink relocation: pull each saveLocation out of the
        # wineprefix into $STROM_GAMEDIR (survives prefix wipes).
        # shellcheck disable=SC2041,SC2043
        for __strom_save in ${lib.escapeShellArgs config.saveLocations}; do
          __strom_src="${config.compatDataPath}/pfx/drive_c/users/steamuser/$__strom_save"
          __strom_dst="$STROM_GAMEDIR/$(basename "$__strom_save")"
          mkdir -p "$__strom_dst"
          if [ -d "$__strom_src" ] && [ ! -L "$__strom_src" ]; then
            cp -an "$__strom_src/." "$__strom_dst/" 2>/dev/null || true
            rm -rf "$__strom_src"
          fi
          mkdir -p "$(dirname "$__strom_src")"
          ln -snf "$__strom_dst" "$__strom_src"
        done
      ''}
    '';

    # Cleanup is handled by an EXIT trap installed in outputs.wrapper.text
    # so it fires even when bash is killed by SIGTERM (gamescope does this
    # when forwarding the WM close). See the comment there.
    postHook = "";

    # Override the default wrapPackage template so PROTON_ARGS can be
    # word-split and spliced in just after the proton binary, before
    # `waitforexitandrun`. Useful for ad-hoc umu-launcher flags without
    # rebuilding the derivation.
    outputs.wrapper = config.pkgs.writeShellApplication {
      name = config.binName;
      runtimeInputs = config.extraPackages;
      text = ''
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: ''export ${n}="${toString v}"'') config.env)}
        ${config.preHook}
        read -ra _proton_extra <<< "''${PROTON_ARGS:-}"

        # EXIT trap fires regardless of how the wrapper bash terminates:
        # umu returning 0, umu returning non-zero (set -e), gamescope
        # SIGTERMing us when it forwards the WM close, ...). Without
        # this, a sway-kill leaves wine system services (winedevice.exe,
        # services.exe) alive in the prefix's wineserver and
        # gamescope's subreaper keeps waiting on them forever.
        # The loop walks /proc inside our private bwrap PID namespace
        # (cross-session safe — each strom game has its own namespace)
        # and SIGKILLs every wine .exe; once they're gone, the
        # gamescopereaper has no descendants, gamescope's waitpid
        # returns, the namespace tears down, the host wrapper unblocks.
        # SIGKILL is critical: wine system services don't honor the
        # SIGTERM that `wineserver -k` sends.
        __strom_kill_wine_exes() {
          local pid_dir comm
          for pid_dir in /proc/[0-9]*; do
            [ -r "$pid_dir/comm" ] || continue
            comm=$(cat "$pid_dir/comm" 2>/dev/null) || continue
            case "$comm" in
              *.exe) kill -KILL "''${pid_dir##*/}" 2>/dev/null || true ;;
            esac
          done
        }
        trap __strom_kill_wine_exes EXIT

        # Belt-and-suspenders watchdog: runs in a backgrounded subshell
        # so it survives even if the wrapper bash is SIGKILLed (trap
        # EXIT would not fire in that case). Polls every 2s; when no
        # game .exe is alive (only wine system services remain), kills
        # the remaining .exes — same logic as the EXIT trap, but in a
        # process that doesn't die with the wrapper.
        (
          set +e
          peaked=0
          empty=0
          while true; do
            sleep 2
            game=0; system=0
            for pid_dir in /proc/[0-9]*; do
              [ -r "$pid_dir/comm" ] || continue
              comm=$(cat "$pid_dir/comm" 2>/dev/null) || continue
              case "$comm" in
                winedevice.exe|services.exe|plugplay.exe|svchost.exe|rpcss.exe \
                |explorer.exe|winemenubuilde|wineboot.exe|conhost.exe|start.exe \
                |tabtip.exe|fontview.exe|rundll32.exe|regsvr32.exe \
                |steam.exe|winebrowser.exe|xalia.exe|crashpad_handle \
                |gpgconf.exe|pingsender.exe|wineconsole.exe|winedbg.exe)
                  system=$((system + 1)) ;;
                *.exe)
                  game=$((game + 1)) ;;
              esac
            done
            if [ "$system" = 0 ] && [ "$game" = 0 ]; then
              # all wine processes gone, we're done
              exit 0
            fi
            if [ "$game" -ge 1 ]; then
              peaked=1; empty=0
            elif [ "$peaked" = 1 ]; then
              empty=$((empty + 1))
              if [ "$empty" -ge 3 ]; then
                echo "strom-proton-watchdog: SIGKILL lingering wine .exes" >&2
                for pid_dir in /proc/[0-9]*; do
                  [ -r "$pid_dir/comm" ] || continue
                  comm=$(cat "$pid_dir/comm" 2>/dev/null) || continue
                  case "$comm" in
                    *.exe) kill -KILL "''${pid_dir##*/}" 2>/dev/null || true ;;
                  esac
                done
                exit 0
              fi
            fi
          done
        ) &
        disown 2>/dev/null || true

        # `|| true` so the trap fires cleanly even if umu returns
        # non-zero (e.g. when a sway-kill propagates as a non-zero
        # exit through wine).
        ${config.exePath} \
          "''${_proton_extra[@]}" \
          ${
            lib.concatMapStringsSep " \\\n  " shellEscape (lib.filter (a: a != "$@") (config.args or [ ]))
          } \
          "$@" || true
        ${config.postHook}
      '';
    };
  };
}
