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
      # the wired Xbox 360 VID/PID (045e:028e) but speak the BLE HoG
      # protocol. SDL's HIDAPI backend latches onto it, drives it as a
      # wired pad, and the game sees a dead controller — meanwhile
      # xpadneo's evdev (where state actually flows) is ignored. Force
      # SDL to skip HIDAPI so it falls back to evdev/js0. Costs PS/
      # Switch-Pro extras (rumble, gyro, touchpad) that ride on HIDAPI;
      # set to "1" per-game via cfg.env if a game needs those.
      SDL_JOYSTICK_HIDAPI = lib.mkDefault "0";
      # 32-bit + 64-bit FHS lib dirs so Proton's loader finds both arches.
      LD_LIBRARY_PATH = lib.mkDefault "/usr/lib32:/usr/lib:/usr/lib64";
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

    # Graceful wineserver shutdown. Process cleanup happens at the bwrap
    # level via --unshare-pid + --die-with-parent.
    postHook = ''
      ${config.package}/files/bin/wineserver -k 2>/dev/null || true
      ${config.package}/files/bin/wineserver -w 2>/dev/null || true
    '';

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
        ${config.exePath} \
          "''${_proton_extra[@]}" \
          ${
            lib.concatMapStringsSep " \\\n  " shellEscape (lib.filter (a: a != "$@") (config.args or [ ]))
          } \
          "$@"
        ${config.postHook}
      '';
    };
  };
}
