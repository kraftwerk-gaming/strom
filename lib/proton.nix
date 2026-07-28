# Proton wrapper: `proton waitforexitandrun <exe>`.
#
# Owns proton-specific concerns: steamclient stub, saveLocations
# relocation, wineprefix auto-wipe on GC, baseline env.
#
# Shutdown:
#   * SIGKILL of the host wrapper (kill -9 <pid>): the outer bwrap's
#     --unshare-pid + --die-with-parent tears the PID namespace down
#     and the kernel SIGKILLs every wine .exe atomically.
#   * sway-kill of the gamescope window (xdg_toplevel.close forwarded
#     by sway): gamescope SIGTERMs its primary child (this wrapper).
#     The TERM/HUP/INT traps below write to /tmp/.strom-control/shutdown.fifo,
#     which the host-side bwrap wrapper (lib/bwrap.nix) is reading in
#     the background. On read return the host SIGKILLs the bwrap PID
#     from outside the namespace, and the kernel atomically tears the
#     ns down. This escapes the gamescope -> gamescopereaper -> winedevice
#     waitpid() chain that would otherwise deadlock shutdown (kill -KILL
#     of PID 1 inside an unshare-pid ns is silently dropped by the
#     kernel, so the deadlock cannot be broken from inside).
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
      description = "Path to the Windows .exe to run.";
    };

    compatDataPath = mkOption {
      type = types.str;
      description = "Path for Proton compatibility data. May contain shell variables.";
    };

    saveLocations = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Paths under drive_c/users/steamuser/ relocated to $STROM_GAMEDIR
        (via symlink) so saves survive wineprefix wipes.
      '';
    };

    autoWipePrefix = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Wipe compatDataPath if drive_c has a broken /nix/store symlink
        (signature of a GC'd default_pfx after a proton bump).
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
        # GStreamer runtime deps for winegstreamer/DirectShow. Proton
        # bundles libgstreamer + its plugins under
        # $PROTON/files/lib/{i386,x86_64}-linux-gnu/{,gstreamer-1.0/} but
        # NOT glib/wayland (it relies on the Steam Linux Runtime container
        # to provide those). Strom has no SLR container, so they must come
        # from the FHS.
        #
        # Wine loads winegstreamer's unix lib (lib/wine/<arch>-unix/
        # winegstreamer.so) with dlopen(RTLD_NOW); that lib is NEEDED-linked
        # against libgstgl-1.0, which in turn NEEDs libwayland-{client,
        # cursor,egl}. If ANY of those is unresolved the whole dlopen fails
        # with STATUS_DLL_NOT_FOUND, gst_init never runs, and winegstreamer's
        # class factory returns E_OUTOFMEMORY (0x8007000e) — DirectShow
        # autoplug then fails to build the graph and games hang on a black
        # screen before any intro movie plays (e.g. GTA: Vice City's
        # Logo.mpg/GTAtitles.mpg). glib additionally needs libz/libffi/
        # libpcre2; buildEnv links only the packages listed here, never
        # their runtime deps, so each must be named explicitly.
        p.glib
        p.zlib
        p.pcre2
        p.libffi
        p.wayland
        p.pkgsi686Linux.freetype
        p.pkgsi686Linux.glibc
        p.pkgsi686Linux.glib
        p.pkgsi686Linux.zlib
        p.pkgsi686Linux.pcre2
        p.pkgsi686Linux.libffi
        p.pkgsi686Linux.wayland
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
        # 32-bit libudev, the counterpart to `p.systemd` in the 64-bit list
        # above. Proton's i386-unix/winepulse.so has libudev.so.1 in its
        # NEEDED, so without this it can never dlopen -- it fails with
        # `err:mmdevapi:load_driver Unable to load UNIX functions:
        # c0000135` and waveOutGetNumDevs() returns 0 for EVERY 32-bit or
        # Win16 Proton game, which presents as a silent game rather than as
        # a missing library. fhs32 shipped 32-bit libpulse and libasound but
        # not this, so the audio stack looked complete and was not.
        # games/homeworld-2 had to add this by hand in its own targetPkgs to
        # get any audio device at all; hoisting it here fixes the class.
        p.pkgsi686Linux.systemd
      ];
      description = ''
        32+64-bit graphics/audio stack proton needs in the FHS at /usr.
        mkGame merges this with cfg.targetPkgs into bwrap.fhsTargetPkgs.
      '';
    };
  };

  config = {
    # mkDefault so a game (or `.override`) can replace the Proton build
    # without lib.mkForce, e.g.
    #   strom.modules.<sys>.<game>.override { proton.package = myProton; }
    package = lib.mkDefault (config.pkgs.callPackage ../pkgs/proton.nix { });
    exePath = "${config.package}/proton";
    binName = lib.mkDefault "proton-wrapper";

    extraPackages = [ config.pkgs.python3 ];

    env = {
      STEAM_COMPAT_DATA_PATH = lib.mkDefault config.compatDataPath;
      STEAM_COMPAT_CLIENT_INSTALL_PATH = lib.mkDefault config.compatDataPath;
      STEAM_COMPAT_APP_ID = lib.mkDefault "0";
      SteamAppId = lib.mkDefault "0";
      SteamGameId = lib.mkDefault "0";
      PROTONFIXES_DISABLE = lib.mkDefault "1";
      DXVK_ASYNC = lib.mkDefault "1";
      # xpadneo's BLE Xbox 360 pads expose the wired 045e:028e
      # VID/PID; SDL's HIDAPI Xbox 360 subdriver latches onto the
      # hidraw and the game sees a dead controller while the working
      # evdev is ignored. Disable HIDAPI for Xbox 360 only so
      # Switch/PS subdrivers stay active. Override per-game if a
      # game needs the wired-360 HIDAPI path.
      SDL_JOYSTICK_HIDAPI_XBOX_360 = lib.mkDefault "0";
      LD_LIBRARY_PATH = lib.mkDefault "/usr/lib32:/usr/lib:/usr/lib64";
      # GE-Proton 10's xalia.exe deadlocks games when no at-spi bus
      # is reachable inside the sandbox.
      PROTON_DISABLE_XALIA = lib.mkDefault "1";
    };

    args = lib.mkOrder 100 [
      "waitforexitandrun"
      config.exe
    ];

    preHook = ''
      mkdir -p "${config.compatDataPath}"

      ${lib.optionalString config.autoWipePrefix ''
        # pkgs/proton-symlink-pfx.patch symlinks default_pfx DLLs from
        # /nix/store into the wineprefix; GC'ing old proton dangles
        # those symlinks and games die at loader_init. Detect and wipe.
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

      # lsteamclient hardcodes $HOME/.steam/sdk{32,64}/steamclient.so
      # and asserts on dlopen failure. The stub satisfies it without
      # a real Steam install.
      mkdir -p "''${HOME:-.}/.steam/sdk32" "''${HOME:-.}/.steam/sdk64"
      ln -sf ${stub}/sdk32/steamclient.so "''${HOME:-.}/.steam/sdk32/steamclient.so"
      ln -sf ${stub}/sdk64/steamclient.so "''${HOME:-.}/.steam/sdk64/steamclient.so"

      ${lib.optionalString (config.saveLocations != [ ]) ''
        # Pull each saveLocation out of the wineprefix into
        # $STROM_GAMEDIR and replace it with a symlink (survives
        # prefix wipes).
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

    postHook = "";

    # PROTON_ARGS: word-split runtime knob spliced in just after the
    # proton binary, before `waitforexitandrun`. Ad-hoc umu-launcher
    # flags without rebuilding.
    outputs.wrapper = config.pkgs.writeShellApplication {
      name = config.binName;
      runtimeInputs = config.extraPackages;
      text = ''
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: ''export ${n}="${toString v}"'') config.env)}
        ${config.preHook}
        read -ra _proton_extra <<< "''${PROTON_ARGS:-}"

        # Sway-kill cleanup signal. Writing one line to the host-side
        # control FIFO wakes the bwrap.nix wrapper's background reader,
        # which then SIGKILLs the bwrap PID from outside the ns. The
        # kernel reaps the ns atomically, taking gamescope, the wine
        # .exes, and this bash with it. `|| true` because if the FIFO
        # is already gone (host wrapper raced ahead on a kill -9) we
        # still want to exit cleanly.
        __strom_request_shutdown() {
          # `<>` opens the FIFO read-write, which (unlike a plain `>`)
          # never blocks on open even if the host-side reader has
          # already returned. One newline is enough for the host's
          # `read -r`; if it already drained and SIGKILLed bwrap, the
          # extra bytes go nowhere harmful.
          [ -n "''${STROM_CONTROL_FIFO:-}" ] && [ -p "$STROM_CONTROL_FIFO" ] || return 0
          { echo shutdown 1>&3; } 3<>"$STROM_CONTROL_FIFO" 2>/dev/null || true
        }
        trap '__strom_request_shutdown; exit 143' TERM
        trap '__strom_request_shutdown; exit 129' HUP
        trap '__strom_request_shutdown; exit 130' INT
        # Normal-exit path (proton returned, game closed cleanly):
        # also poke the FIFO so the host wrapper drops out of its read
        # promptly instead of waiting on bwrap's natural exit.
        trap '__strom_request_shutdown' EXIT

        # `|| true` so the EXIT trap fires cleanly even when proton
        # returns non-zero (e.g. when SIGTERM propagates through wine
        # as a non-zero exit on sway-kill).
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
