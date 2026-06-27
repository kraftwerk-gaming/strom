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
# read-write overlay over the nix-store game data is mounted with patched
# fuse-overlayfs (kernel --overlay can't make 0555 store lowers writable
# in this single-uid userns) INSIDE the bwrap namespace by the inner
# script, so it auto-vanishes with the namespace on teardown. No nested
# buildFHSEnv.
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

  # Patched fuse-overlayfs (squash_to_uid + copy-up mode-OR) for the
  # read-write game overlay, mounted INSIDE the bwrap namespace by the
  # inner script below so it auto-vanishes with the namespace on any
  # teardown (no host mount/daemon to leak). Both binaries are referenced
  # by store path (reachable inside via the /nix ro-bind); fusermount3 is
  # the PLAIN store helper (NOT the host setuid /run/wrappers one): inside
  # the userns the caller holds CAP_SYS_ADMIN, so the unprivileged
  # mount(2) the helper performs is permitted without setuid.
  fuseOverlayfs = pkgs.callPackage ../pkgs/fuse-overlayfs.nix { inherit pkgs; };
  fusermount3Bin = "${pkgs.fuse3}/bin/fusermount3";

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
        enableGamescope = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether the entrypoint runs the game nested inside gamescope.
            Every game wrapper additionally exposes a `no-gamescope` passthru
            built with this set to false, which renders directly to the host
            display (still bwrap-sandboxed + proton'd) — run it with
            `nix run .#<game>.no-gamescope`.
          '';
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
              # Don't bind host "/" as the root: bwrap's default root is
              # a writable tmpfs, which lets the FHS binds (/usr /bin /lib
              # /lib64 in strom-fhs.nix) mkdir their own mountpoints even
              # on hosts that lack a top-level /lib. A read-only --ro-bind
              # / / root could only bind onto pre-existing host dirs and so
              # aborted on hosts without /lib. We re-add just the host dirs
              # games need: /nix (store), /etc (resolv.conf, fonts, ssl,
              # machine-id) and /sys (DRM/Vulkan + wayland device probing —
              # without it radv can't enumerate and gamescope falls back to
              # llvmpipe). /run + /tmp are bound RW below; /dev /proc via
              # dev-bind/proc.
              ro-bind = {
                "/nix" = "/nix";
                "/etc" = "/etc";
                "/sys" = "/sys";
              };
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

              # /tmp/.strom-overlay (not /strom/overlay): /tmp is RW from
              # the earlier --bind /tmp /tmp, a known-writable mountpoint.
              # bwrap.nix creates this dir (--dir) inside the namespace; the
              # inner script (command, below) mounts fuse-overlayfs onto it
              # IN-NS so it auto-vanishes with the namespace on teardown.
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

                # Clear any stale n2n IP marker from a previous run so a launch
                # without $N2N_SUPERNODE can't report an old overlay IP. The
                # in-sandbox edge launcher rewrites it only if n2n actually
                # comes up this launch (see lib/n2n-edge-launcher.sh).
                rm -f "$STROM_GAMEDIR/.strom-n2n-ip"

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
              # Inner script (inside bwrap): mount the RW overlay in-ns,
              # cd to it, shader cache, preRun, exec the runtime entrypoint.
              command = "${pkgs.writeShellScript "${cfg.name}-inner" ''
                set -euo pipefail

                # Mount the read-write game overlay INSIDE this namespace.
                # bwrap granted CAP_SYS_ADMIN over its own userns/mountns
                # (see lib/bwrap.nix --cap-add), so the unprivileged mount(2)
                # that fusermount3 performs is permitted. squash_to_uid
                # presents the 0555 root-owned nix-store lowers as
                # caller-owned + writable; the copy-up patch keeps copied-up
                # dirs writable, so the engine can create any file on demand.
                # Only written content lands in the upper ($STROM_GAMEDIR).
                # libfuse spawns fusermount3 by PATH lookup, so the plain
                # store fuse3 must be reachable -- prepend it (and set
                # FUSERMOUNT_PROG belt-and-suspenders). The daemon lives in
                # this pid-ns and dies with it on any teardown (SIGKILL
                # included), so nothing host-side can leak.
                export PATH="${pkgs.fuse3}/bin:''${PATH:-}"
                export FUSERMOUNT_PROG="${fusermount3Bin}"
                ${fuseOverlayfs}/bin/fuse-overlayfs \
                  -o "lowerdir=${lib.concatStringsSep ":" cfg.bwrap.overlay.lowers},upperdir=$STROM_GAMEDIR,workdir=$STROM_CACHEDIR/overlay-work,squash_to_uid=$(id -u),squash_to_gid=$(id -g)" \
                  "$STROM_OVERLAY"
                if ! ${pkgs.util-linux}/bin/mountpoint -q "$STROM_OVERLAY"; then
                  echo "${cfg.name}: in-ns overlay mount at $STROM_OVERLAY failed" >&2
                  exit 1
                fi

                export GAMEDIR="$STROM_OVERLAY"
                cd "$GAMEDIR"

                GAMECACHE="''${HOME:-.}/.cache/strom/${cfg.name}/shadercache"
                mkdir -p "$GAMECACHE"
                export MESA_SHADER_CACHE_DIR="$GAMECACHE"
                export DXVK_STATE_CACHE_PATH="$GAMECACHE"

                ${lib.optionalString cfg.n2n.enable ''
                  # n2n edge inside the sandbox (own netns + slirp4netns
                  # connector wired up host-side). Runs only when
                  # $N2N_SUPERNODE is set; otherwise this fragment is a
                  # no-op and the game keeps the shared host net. The
                  # readiness FIFO lives in the host control dir bound at
                  # /tmp/.strom-control; the host writes one byte to it
                  # after slirp has tap0 + the default route up.
                  STROM_N2N_EDGE=${cfg.n2n.package}/bin/edge
                  STROM_N2N_COMMUNITY=${lib.escapeShellArg cfg.n2n.community}
                  STROM_N2N_READY_FIFO=/tmp/.strom-control/n2n-ready.fifo
                  STROM_N2N_EXTRA_ARGS=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.n2n.extraEdgeArgs)})
                  ${builtins.readFile ./n2n-edge-launcher.sh}
                  ${lib.optionalString cfg.n2n.defaultRoute ''
                    # n2n.defaultRoute (build-time templated, only for this
                    # game): move the default route onto edge0 so the game reports
                    # the overlay address. Diablo II's TCP/IP host screen picks
                    # "my IP" by BEST-ROUTE to the internet (not the literal
                    # default-gateway adapter -- the /1 OpenVPN trick was tried and
                    # made D2 pick slirp's tap0 address), so internet egress must
                    # be edge0; only the supernode keeps a pin-hole out tap0 so the
                    # n2n control channel survives (LAN play needs no other
                    # internet). The supernode's IP is resolved host-side (see the
                    # n2n bwrap.extraPreHook -> STROM_N2N_SUPERNODE_IP) because the
                    # netns has no DNS and `ip route add <hostname>` fails -- that
                    # bare-hostname pin was the "supernode not responding" bug.
                    # Overlay peers stay on-link via edge0's /24. Event-driven
                    # (own `ip monitor` wait), no poll.
                    (
                      exec {__strom_dr_mon}< <(exec ip monitor link address 2>/dev/null)
                      until ip -4 addr show edge0 2>/dev/null | grep -q 'inet '; do
                        IFS= read -r _ <&"''${__strom_dr_mon}" || break
                      done
                      # Parse `ip -j` (JSON) with jq, not positional awk/sed.
                      __strom_dr_tap_gw=$(ip -j -4 route show default 2>/dev/null \
                        | ${pkgs.jq}/bin/jq -r '.[0].gateway // empty')
                      __strom_dr_edge_ip=$(ip -j -4 addr show edge0 2>/dev/null \
                        | ${pkgs.jq}/bin/jq -r '[.[].addr_info[]? | select(.family == "inet") | .local][0] // empty')
                      # Pin the supernode (its IP was resolved host-side into
                      # STROM_N2N_SUPERNODE_IP) FIRST, so it never drops -- tap0
                      # is still the default here. Then move the default to edge0.
                      if [ -n "''${__strom_dr_tap_gw:-}" ] && [ -n "''${STROM_N2N_SUPERNODE_IP:-}" ]; then
                        ip route add "$STROM_N2N_SUPERNODE_IP" via "$__strom_dr_tap_gw" dev tap0 2>/dev/null || true
                      fi
                      if [ -n "''${__strom_dr_edge_ip:-}" ]; then
                        # nominal on-link gateway = .1 of edge0's /24 overlay
                        ip route replace default via "''${__strom_dr_edge_ip%.*}.1" dev edge0 2>/dev/null || true
                      fi
                    ) &
                  ''}
                ''}

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

        n2n = mkOption {
          type = wrapperType ./n2n.nix { };
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.padToKb.enable {
          # pad-to-kb starts its evsieve helper in preHook (pre-exec) and
          # reaps it via an EXIT/TERM trap that `exec strom-run` would
          # discard, leaving the evsieve uinput device behind. Keep padToKb
          # games on the legacy bash supervision until the helper is
          # migrated. (n2n needs no build-time opt-out: it is inert unless
          # $N2N_SUPERNODE is set at runtime, and bwrap.nix only hands off
          # to strom-run when it is unset.)
          bwrap.useStromRun = false;
        })

        (lib.mkIf (cfg.runtime == "proton") {
          # tmpfs $HOME so proton.preHook can write ~/.steam/sdk{32,64}/.
          # (/sys is bound universally above for DRM/Vulkan probing.)
          bwrap.tmpfs = [ "$HOME" ];

          # Extend the universal FHS with proton's graphics/audio stack
          # and turn on multilib (/usr/lib32 for 32-bit Wine).
          bwrap.fhsTargetPkgs = lib.mkForce (p: cfg.proton.fhsTargetPkgs p ++ cfg.targetPkgs p);
          bwrap.fhsMultilib = true;

          proton.exe = overlayExe;
          proton.env = cfg.env;
          gamescope.command = lib.getExe cfg.proton.outputs.wrapper;
          entrypoint =
            if cfg.enableGamescope then
              lib.getExe cfg.gamescope.outputs.wrapper
            else
              lib.getExe cfg.proton.outputs.wrapper;
        })

        (lib.mkIf (cfg.runtime == "native") (
          let
            # If a runScript is set it becomes the inner command (env
            # exports / mkdir / config bootstrap before the real exec);
            # otherwise the executable is launched directly. Reused as both
            # the gamescope inner command and the no-gamescope entrypoint.
            nativeCommand =
              if cfg.runScript != null then
                "${pkgs.writeShellScript "${cfg.name}-runscript" cfg.runScript}"
              else
                overlayExe;
          in
          {
            # $STROM_GAMEDIR -> $HOME so XDG saves persist.
            bwrap.bind."$HOME" = "$STROM_GAMEDIR";
            bwrap.env = cfg.env;

            gamescope.command = nativeCommand;
            entrypoint =
              if cfg.enableGamescope then lib.getExe cfg.gamescope.outputs.wrapper else nativeCommand;
          }
        ))

        (lib.mkIf (cfg.runtime == "retroarch") {
          retroarch.romPath = overlayExe;
          # RetroArch's vulkan WSI connects to gamescope's wayland; gamescope
          # only serves a usable wayland display to clients when --expose-wayland
          # is set (without it the client gets "Failed to create wl_display" and
          # renders black). Every wayland game under gamescope sets this.
          gamescope.flags."--expose-wayland" = lib.mkDefault true;
          gamescope.command = lib.getExe cfg.retroarch.outputs.wrapper;
          entrypoint =
            if cfg.enableGamescope then
              lib.getExe cfg.gamescope.outputs.wrapper
            else
              lib.getExe cfg.retroarch.outputs.wrapper;
        })

        (lib.mkIf (cfg.runtime == "pcsx2") {
          pcsx2.isoPath = overlayExe;
          # NB: PCSX2 must NOT use gamescope's wayland — its Qt wayland backend
          # renders the game into a subsurface gamescope can't create (grey
          # screen + VM stall). pcsx2.nix forces QT_QPA_PLATFORM=xcb so it runs
          # on the nested Xwayland instead; hence no --expose-wayland here.
          gamescope.command = lib.getExe cfg.pcsx2.outputs.wrapper;
          entrypoint =
            if cfg.enableGamescope then
              lib.getExe cfg.gamescope.outputs.wrapper
            else
              lib.getExe cfg.pcsx2.outputs.wrapper;
        })

        (lib.mkIf cfg.n2n.enable {
          # Host-side netns plumbing on bwrap's GENERIC hooks (bwrap.nix
          # knows nothing of n2n). All inert until $N2N_SUPERNODE is set;
          # the in-sandbox edge launcher is sourced into the inner command
          # above.
          #
          # Fully EVENT-DRIVEN — no poll/sleep anywhere. Readiness rides
          # the fds the primitives already expose:
          #   * bwrap --info-fd      -> blocking-read the in-ns child-pid
          #   * slirp4netns --ready-fd -> blocking-read "network is up"
          #   * slirp4netns --exit-fd  -> slirp self-terminates when the
          #     wrapper dies (its write end auto-closes). THIS IS THE
          #     ENTIRE TEARDOWN: no reap function, no cleanupHook, no
          #     trap folding.
          # All FIFOs live in $STROM_CONTROL_DIR, which the existing
          # generic EXIT trap in bwrap.nix already rm -rf's.
          bwrap.extraPackages = [
            cfg.n2n.connectorPackage
            pkgs.jq
          ];

          # Before launch: give the sandbox its own netns + tun +
          # CAP_NET_ADMIN, and capture the in-ns child-pid via --info-fd
          # (the outer bwrap is in the parent netns, so $BWRAP_PID is the
          # wrong target). Only the info FIFO is opened here — bwrap MUST
          # inherit its write end. It is opened read+write (<>) so the
          # open() never blocks on a missing peer; the wrapper only reads.
          # The slirp ready/exit FIFOs are deliberately NOT opened until
          # postLaunchHook (after bwrap forks) so the sandbox never inherits
          # the host-side control fds. No supernode -> scrub N2N_SUPERNODE so
          # the in-sandbox launcher stays inert and the sandbox keeps host
          # net.
          bwrap.extraPreHook = ''
            if [ -n "''${N2N_SUPERNODE:-}" ]; then
              mkfifo -m 0600 \
                "$STROM_CONTROL_DIR/n2n-info" \
                "$STROM_CONTROL_DIR/n2n-slirp-ready" \
                "$STROM_CONTROL_DIR/n2n-slirp-exit" \
                "$STROM_CONTROL_DIR/n2n-ready.fifo"
              exec {STROM_N2N_INFO_FD}<>"$STROM_CONTROL_DIR/n2n-info"
              BWRAP_ARGS="''${BWRAP_ARGS:-} --unshare-net --cap-add CAP_NET_ADMIN --dev-bind /dev/net/tun /dev/net/tun --setenv N2N_SUPERNODE $N2N_SUPERNODE --info-fd $STROM_N2N_INFO_FD"
              # Resolve the supernode's host part to an IP HERE on the host --
              # the sandbox netns has no working DNS, so the in-ns edge cannot
              # resolve a hostname (n2n's supernode2sock fails with EAI_AGAIN).
              # Host-side is one clean lookup with no in-netns mgmt-port/retry
              # plumbing. `dig +short` prints address lines (keep the first
              # IPv4); an IP literal passes straight through. ALWAYS set when
              # N2N_SUPERNODE is set: the edge uses it for -l, and
              # n2n.defaultRoute additionally pins a route to it.
              __strom_sn="''${N2N_SUPERNODE%%:*}"
              if printf '%s' "$__strom_sn" | grep -qE '^[0-9.]+$'; then
                __strom_sn_ip="$__strom_sn"
              else
                __strom_sn_ip=$(${pkgs.dnsutils}/bin/dig +short "$__strom_sn" A 2>/dev/null \
                  | grep -m1 -E '^[0-9.]+$' || true)
              fi
              [ -n "$__strom_sn_ip" ] \
                && BWRAP_ARGS="$BWRAP_ARGS --setenv STROM_N2N_SUPERNODE_IP $__strom_sn_ip"
            else
              BWRAP_ARGS="''${BWRAP_ARGS:-} --unsetenv N2N_SUPERNODE"
            fi
          '';

          # After launch: a LINEAR sequence of blocking reads, no loops on
          # the network state, no sleep.
          #   1. Block-read the child-pid bwrap wrote to the info fd. bwrap
          #      pretty-prints a multi-line JSON object then keeps the fd
          #      open, so we read lines until the closing brace (an
          #      event-driven blocking read, NOT a poll) and feed the blob
          #      to jq.
          #   2. Start slirp4netns with --ready-fd / --exit-fd. slirp NATs
          #      the netns to the real network so the in-ns edge can reach
          #      the supernode (pasta can't: it rewrites the UDP source and
          #      n2n rejects the ACK). Every FIFO end is opened STRICTLY
          #      single-direction (slirp gets ready write-only + exit
          #      read-only in its own subshell; the wrapper gets ready
          #      read-only + exit write-only). Single-direction opens are
          #      essential: a <> open would give the wrapper a self-write
          #      dup that masks the ready EOF and the exit POLLHUP, and the
          #      reads/teardown would hang. Both helper subshells open by
          #      PATH so they never inherit the sibling direction.
          #   3. Block-read slirp's ready fd ONCE — slirp writes "1" when
          #      tap0 + the default route are up, then closes it.
          #   4. Write one byte to the in-sandbox readiness FIFO the edge
          #      launcher is blocking on; it then brings up edge0.
          #
          # Teardown: the wrapper holds the exit-fd WRITE end for its whole
          # lifetime; when the wrapper exits by ANY path that fd closes,
          # slirp gets POLLHUP on its read end and terminates on its own.
          # THIS IS THE ENTIRE TEARDOWN — no kill, no reap, no trap, no
          # cleanupHook. The FIFOs live in $STROM_CONTROL_DIR, which the
          # existing generic EXIT trap in bwrap.nix already removes.
          bwrap.postLaunchHook = ''
            if [ -n "''${N2N_SUPERNODE:-}" ]; then
              __strom_n2n_json=
              while IFS= read -r __strom_n2n_line <&"$STROM_N2N_INFO_FD"; do
                __strom_n2n_json="$__strom_n2n_json$__strom_n2n_line"
                case "$__strom_n2n_line" in "}") break ;; esac
              done
              exec {STROM_N2N_INFO_FD}<&-
              __strom_n2n_child=$(printf '%s' "$__strom_n2n_json" | jq -r '."child-pid"' 2>/dev/null)
              if [ -n "$__strom_n2n_child" ] && [ "$__strom_n2n_child" != null ]; then
                (
                  # slirp's own fds: exit read-only THEN ready write-only.
                  # Opened by path here so this subshell never holds the
                  # sibling (write) end of exit nor the (read) end of ready.
                  # Order mirrors the wrapper's opens below so each FIFO's
                  # two ends rendezvous in lockstep (exit pair first, then
                  # ready pair) — opening them in opposite orders on the two
                  # sides would deadlock.
                  exec {__strom_exit_rd}<"$STROM_CONTROL_DIR/n2n-slirp-exit"
                  exec {__strom_ready_wr}>"$STROM_CONTROL_DIR/n2n-slirp-ready"
                  exec ${cfg.n2n.connectorPackage}/bin/slirp4netns --configure --disable-dns \
                    --ready-fd "$__strom_ready_wr" \
                    --exit-fd "$__strom_exit_rd" \
                    "$__strom_n2n_child" tap0 >&2
                ) &
                # Rendezvous with slirp's opens, same order (exit then
                # ready). The exit WRITE end is held for the wrapper's whole
                # lifetime — its close is the teardown trigger (never
                # referenced again on purpose).
                # shellcheck disable=SC2034
                exec {STROM_N2N_SLIRP_EXIT_FD}>"$STROM_CONTROL_DIR/n2n-slirp-exit"
                exec {STROM_N2N_SLIRP_READY_FD}<"$STROM_CONTROL_DIR/n2n-slirp-ready"
                # Block until slirp writes "1"; its close then EOFs our read.
                IFS= read -r _ <&"$STROM_N2N_SLIRP_READY_FD" || true
                exec {STROM_N2N_SLIRP_READY_FD}<&-
                # Release the in-sandbox edge launcher (it opened the read
                # end of this FIFO <>, so this write does not block).
                echo ready > "$STROM_CONTROL_DIR/n2n-ready.fifo"
              else
                echo "n2n: could not read child-pid from bwrap --info-fd; edge will have no network" >&2
              fi
            fi
          '';
        })

        (lib.mkIf (cfg.runtime == "custom") (
          let
            nativeCommand =
              if cfg.runScript != null then
                "${pkgs.writeShellScript "${cfg.name}-runscript" cfg.runScript}"
              else
                overlayExe;
          in
          {
            # Like native (HOME -> $STROM_GAMEDIR); FHS at /usr is on by
            # default for bare-soname dlopen of bundled libs.
            # `bwrap.fhsMultilib = true` opt-in for 32-bit games.
            bwrap.bind."$HOME" = "$STROM_GAMEDIR";
            bwrap.env = cfg.env;

            gamescope.command = nativeCommand;
            entrypoint =
              if cfg.enableGamescope then lib.getExe cfg.gamescope.outputs.wrapper else nativeCommand;
          }
        ))

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

  # Instantiate the game from a spec and attach strom passthrus to its
  # wrapper derivation:
  #
  #   .override overrides  - re-instantiate the game with `overrides`
  #                          deep-merged into the spec (chainable), e.g.
  #                            strom.packages.<sys>.<game>.override {
  #                              proton.package = myProton;
  #                            }
  #   .no-gamescope        - the same game rendered directly to the host
  #                          display instead of nested in gamescope:
  #                            nix run .#<game>.no-gamescope
  #
  # Both are simply the game re-instantiated from a modified spec, so
  # they take the exact same `.apply` evaluation path as the base build.
  # That sidesteps the wrapper-module API entirely: no `.extend` (whose
  # results expose `.config.outputs` instead of `.outputs` and are not
  # re-extendable) and no mkForce — `recursiveUpdate` / `//` replace the
  # option in the spec, even one the game's own spec pins (enableGamescope).
  # The passthrus are lazy, so the recursion only unfolds as far as you
  # reach, and they ride every attr path to the wrapper
  # (packages.<sys>.<game>, legacyPackages.<sys>.games.<game>, ...).
  mkWrapper =
    spec:
    ((wlib.wrapModule gameModule).apply spec).outputs.wrapper.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        override = overrides: mkWrapper (lib.recursiveUpdate spec overrides);
        no-gamescope = mkWrapper (spec // { enableGamescope = false; });
      };
    });
in
configured
// {
  outputs = configured.outputs // {
    wrapper = mkWrapper cleanedSpec;
  };
}
