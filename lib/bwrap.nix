# Single bwrap sandbox: host FS view + FHS at /usr (via strom-fhs.nix) +
# overlay over the nix-store game data + --unshare-pid/--die-with-parent
# for kernel-enforced cleanup. The wrapped binary is bwrap itself;
# config.command is appended after `bwrap [flags] --`.
#
# Option values may contain shell variables ($HOME, $STROM_GAMEDIR);
# they expand at wrapper runtime.
{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    optionals
    concatLists
    concatMapStringsSep
    mapAttrsToList
    ;
  renderPairs =
    flag: pairs:
    concatLists (
      mapAttrsToList (dest: src: [
        flag
        src
        dest
      ]) pairs
    );
  renderSingles =
    flag: paths:
    concatLists (
      map (p: [
        flag
        p
      ]) paths
    );
  shellEscape = arg: ''"${arg}"'';

  # Patched fuse-overlayfs (squash_to_uid + copy-up mode-OR) for the
  # read-write game overlay. fusermount3 (mount/unmount) is the host's
  # setuid /run/wrappers/bin/fusermount3, reached via the appended $PATH
  # (we must NOT ship fuse3 here — see extraPackages).
  fuseOverlayfs = config.pkgs.callPackage ../pkgs/fuse-overlayfs.nix {
    inherit (config) pkgs;
  };

  # Native supervisor that owns the game process tree via cgroup v2 and
  # tears it down atomically (see pkgs/strom-run). Used on the common
  # launch path; the legacy host-side bash below stays for the n2n-LAN
  # runtime path and padToKb games.
  stromRun = config.pkgs.callPackage ../pkgs/strom-run { };

  fhs =
    (import ./strom-fhs.nix {
      inherit (config) pkgs;
      inherit lib;
    })
      {
        targetPkgs = config.fhsTargetPkgs;
        multilib = config.fhsMultilib;
        name = config.binName;
      };
in
{
  _class = "wrapper";

  options = {
    command = mkOption {
      type = types.either types.path types.str;
      description = "Target program to exec inside the sandbox.";
    };

    unshare-pid = mkOption {
      type = types.bool;
      default = false;
    };
    unshare-net = mkOption {
      type = types.bool;
      default = false;
    };
    share-net = mkOption {
      type = types.bool;
      default = false;
    };
    die-with-parent = mkOption {
      type = types.bool;
      default = true;
    };

    useStromRun = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Emit the native strom-run hand-off (cgroup v2 atomic teardown) on
        the common launch path. At runtime the hand-off is taken only when
        no n2n overlay is active ($N2N_SUPERNODE unset); the n2n-LAN path
        falls through to the legacy bash supervision. mk-game disables this
        for padToKb games, whose evsieve helper relies on the legacy traps.
      '';
    };

    ro-bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    ro-bind-try = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    bind-try = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    dev-bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    tmpfs = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    proc = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };
    chdir = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    setenv = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };
    chmod = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };

    fhsTargetPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = _: [ ];
      description = ''
        FHS userspace contents on top of the baseline (glibc, coreutils,
        bash). 64-bit as `p.foo`, 32-bit as `p.pkgsi686Linux.foo`.
      '';
    };
    fhsMultilib = mkOption {
      type = types.bool;
      default = false;
      description = "Build a 32-bit /usr/lib32 tree (Wine / multilib).";
    };

    overlay = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            lowers = mkOption {
              type = types.listOf types.str;
              description = ''
                Read-only overlay lower layers in priority order: the
                first entry is closest to upper (highest priority); each
                later entry is deeper (lower priority, masked by earlier
                ones on path conflicts). Joined left-to-right into the
                fuse-overlayfs `lowerdir=` (same convention).
              '';
            };
            upper = mkOption { type = types.str; };
            work = mkOption { type = types.str; };
            dest = mkOption { type = types.str; };
          };
        }
      );
      default = null;
      description = ''
        Read-write overlay over read-only nix-store game data, mounted
        on the host with patched fuse-overlayfs (preHook) and bound into
        the sandbox at `dest`. `lowers` is the stacked read-only layer
        list (first = highest priority, e.g. mods; last = base, e.g.
        nix-store game data). `upper` takes writes; `work` is the
        overlay scratch dir.
      '';
    };

    extraPreHook = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra shell commands before bwrap launches. types.lines, so
        multiple definitions concatenate (unlike upstream preHook).

        Runs host-side after preHook and BEFORE bwrap reads $BWRAP_ARGS
        into its argv; a hook may append flags to $BWRAP_ARGS and set up
        file descriptors here.
      '';
    };

    postLaunchHook = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Shell commands spliced in immediately after bwrap is launched in
        the background, with $BWRAP_PID in scope. For starting helper
        processes whose lifetime is tied to the sandbox. types.lines, so
        multiple definitions concatenate.
      '';
    };

    cleanupHook = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Shell commands run on sandbox teardown. Folded into BOTH the
        wrapper EXIT trap and the host-cleanup function, so the body
        MUST be idempotent. For reaping helper processes started in
        postLaunchHook and removing temp files. Interpolated into a
        single-quoted trap string, so it must not contain single quotes.
        types.lines, so multiple definitions concatenate.
      '';
    };
  };

  config = {
    package = config.pkgs.bubblewrap;
    binName = lib.mkDefault "bwrap-wrapper";

    env = lib.mapAttrs (_: v: lib.mkDefault v) fhs.env;

    # NixOS has /run/current-system/sw/bin on PATH but no /usr/bin;
    # without this, bwrap inherits the host PATH and /usr/bin/mono etc.
    # from the FHS are unreachable.
    setenv.PATH = lib.mkDefault "/usr/bin:/usr/sbin:/usr/local/bin:/run/current-system/sw/bin";

    # Patched fuse-overlayfs on the host wrapper's PATH (overlay mount).
    # We deliberately do NOT add fuse3 here: its fusermount3 is plain
    # (non-setuid) and would shadow the host's setuid
    # /run/wrappers/bin/fusermount3 (reached via the appended $PATH).
    # Unmounting an existing fuse mount needs that setuid helper —
    # the non-setuid one fails with EPERM — and fuse-overlayfs also
    # finds the setuid helper for the mount.
    extraPackages = lib.optionals (config.overlay != null) [ fuseOverlayfs ];

    # Mount the read-write game overlay on the HOST with patched
    # fuse-overlayfs before bwrap launches; the recursive `--bind` in
    # args carries it into the sandbox at `overlay.dest`. Runs in
    # extraPreHook (concatenated AFTER preHook), so $STROM_CACHEDIR /
    # overlay-work are already set up by the time we mount.
    extraPreHook = lib.optionalString (config.overlay != null) ''
      # Tear down any stale mount from a crashed prior run, then mount
      # the merged tree. squash_to_uid presents the 0555 root-owned
      # nix-store lowers as caller-owned + writable; the copy-up patch
      # keeps copied-up dirs writable, so the engine can create any new
      # file on demand. Only written content lands in the upper
      # ($STROM_GAMEDIR); nothing is predeclared.
      STROM_OVERLAY_MERGED="$STROM_CACHEDIR/overlay-merged"
      export STROM_OVERLAY_MERGED
      if mountpoint -q "$STROM_OVERLAY_MERGED" 2>/dev/null; then
        fusermount3 -u "$STROM_OVERLAY_MERGED" 2>/dev/null || true
      fi
      mkdir -p "$STROM_OVERLAY_MERGED"
      # `9<&-` closes the single-instance lock fd for the fuse-overlayfs
      # daemon ONLY. mk-game's preHook opened the flock as fd 9 (`exec
      # 9>.../.lock`) and strom-run inherits it across exec to hold the
      # lock for the launch's lifetime. fuse-overlayfs is a plain child of
      # this wrapper, so without this it ALSO inherits fd 9 -- and because
      # an flock is held until EVERY fd to that open-file-description is
      # closed, an overlay daemon that outlives strom-run keeps the lock
      # held forever (observed: an orphaned fuse-overlayfs pinned the lock
      # after the game exited). Closing fd 9 here means only strom-run can
      # hold the lock, so it is always released when strom-run is reaped.
      # No-op when fd 9 is unopened (non-proton runtimes don't flock).
      fuse-overlayfs \
        -o "lowerdir=${lib.concatStringsSep ":" config.overlay.lowers},upperdir=${config.overlay.upper},workdir=${config.overlay.work},squash_to_uid=$(id -u),squash_to_gid=$(id -g)" \
        "$STROM_OVERLAY_MERGED" 9<&-
    '';

    # Note: the host fuse-overlayfs unmount is handled by the EXIT trap
    # in outputs.wrapper (covers normal exit AND the TERM/INT/HUP path,
    # which never reaches postHook), not here.

    # Argv order: --ro-bind / / first, then FHS overrides at /usr+/bin+
    # /lib, then RW binds, then tmpfs carve-outs, then bind-try inside
    # them, then proc/dev, then --overlay. --bind before --tmpfs because
    # re-binding a tmpfs's parent wipes it.
    args = lib.mkOrder 100 (
      optionals config.unshare-pid [ "--unshare-pid" ]
      ++ optionals config.unshare-net [ "--unshare-net" ]
      ++ optionals config.share-net [ "--share-net" ]
      ++ optionals config.die-with-parent [ "--die-with-parent" ]
      ++ renderPairs "--ro-bind" config.ro-bind
      ++ fhs.bwrapArgs
      ++ renderPairs "--bind" config.bind
      ++ renderSingles "--tmpfs" config.tmpfs
      # Bind a host-side control directory at /tmp/.strom-control so the
      # inner runtime wrapper can signal "please shut down" via FIFO
      # write (see proton.nix). The host wrapper's background reader
      # picks the write up and SIGKILLs the bwrap PID from outside the
      # namespace — necessary because kill -KILL of PID 1 inside an
      # unshare-pid namespace is silently ignored by the kernel, so
      # neither the inner bash nor gamescope can tear the ns down on
      # its own when gamescopereaper is stuck waiting on winedevice.
      ++ [
        "--bind"
        "$STROM_CONTROL_DIR"
        "/tmp/.strom-control"
        "--setenv"
        "STROM_CONTROL_FIFO"
        "/tmp/.strom-control/shutdown.fifo"
      ]
      ++ renderPairs "--ro-bind-try" config.ro-bind-try
      ++ renderPairs "--bind-try" config.bind-try
      ++ renderSingles "--proc" config.proc
      ++ renderPairs "--dev-bind" config.dev-bind
      # Bind the host-side fuse-overlayfs merged tree (mounted in the
      # preHook below) into the sandbox at the overlay dest. We use
      # patched fuse-overlayfs instead of the kernel `--overlay` because
      # the nix-store lowers are 0555 root-owned and, in this single-uid
      # userns, map to the unmapped 65534 so CAP_DAC_OVERRIDE never
      # applies -- kernel overlayfs leaves any lower-only subdir
      # permanently unwritable. fuse-overlayfs with squash_to_uid +
      # the copy-up mode-OR patch presents every dir as caller-owned and
      # writable, so the engine can create ANY new file on demand with
      # ZERO predeclaration; only actual writes land in the upper
      # ($STROM_GAMEDIR). The bind is recursive, so the fuse mount made
      # on the host is carried into the namespace.
      ++ optionals (config.overlay != null) [
        "--bind"
        "$STROM_CACHEDIR/overlay-merged"
        config.overlay.dest
      ]
      ++ optionals (config.chdir != null) [
        "--chdir"
        config.chdir
      ]
      ++ concatLists (
        mapAttrsToList (name: value: [
          "--setenv"
          name
          value
        ]) config.setenv
      )
      ++ concatLists (
        mapAttrsToList (path: mode: [
          "--chmod"
          mode
          path
        ]) config.chmod
      )
    );

    # bwrap launches in the background with $BWRAP_PID captured so the
    # TERM/INT/HUP traps can forward host-side signals promptly (without
    # this, bash defers delivery until `wait` returns).
    #
    # BWRAP_ARGS: runtime-injected bwrap flags spliced in before `--`,
    # e.g. BWRAP_ARGS="--bind /home/me/saves /home/me/saves".
    #
    # Shutdown protocol:
    #   * Host-side SIGTERM/INT/HUP of this wrapper -> trap kills bwrap.
    #   * SIGKILL of this wrapper -> --die-with-parent tears the ns down.
    #   * Inner write to /tmp/.strom-control/shutdown.fifo -> background
    #     reader returns from `read`, then SIGKILLs bwrap from outside
    #     the namespace. This is the escape hatch for the gamescope ->
    #     gamescopereaper -> winedevice.exe waitpid() deadlock that
    #     prevents PID-ns-internal teardown (kill -KILL of pid 1 inside
    #     an unshare-pid namespace is dropped by the kernel safeguard).
    outputs.wrapper = config.pkgs.writeShellApplication {
      name = config.binName;
      runtimeInputs = [
        config.pkgs.bubblewrap
      ]
      ++ lib.optionals config.useStromRun [ stromRun ]
      ++ config.extraPackages;
      text =
        let
          # bwrap argv (minus the wrapper.nix-injected "$@", placed after
          # ${command}); rendered once, used by the strom-run hand-off and
          # the legacy launch below.
          bwrapArgs = concatMapStringsSep " \\\n          " shellEscape (
            lib.filter (a: a != "$@") (config.args or [ ])
          );
          stromRunArgs = lib.concatStringsSep " " (
            [
              "--cgroup-name"
              ''"strom-${config.binName}"''
              "--control-dir"
              ''"$STROM_CONTROL_DIR"''
              "--control-fifo"
              ''"$STROM_CONTROL_DIR/shutdown.fifo"''
              "--gs-dirs"
              ''"$STROM_CONTROL_DIR/strom-gs-dirs"''
            ]
            ++ lib.optionals (config.overlay != null) [
              "--overlay-unmount"
              ''"$STROM_CACHEDIR/overlay-merged"''
              "--fusermount3"
              "fusermount3"
            ]
          );
        in
        ''
          ${lib.concatStringsSep "\n" (mapAttrsToList (n: v: ''export ${n}="${toString v}"'') config.env)}

          # Host-side control FIFO. Created BEFORE preHook so that hook
          # output can reference STROM_CONTROL_DIR if needed; bind-mounted
          # into the bwrap at /tmp/.strom-control by the --bind argv above.
          STROM_CONTROL_DIR=$(mktemp -d -t strom-ctl.XXXXXX)
          export STROM_CONTROL_DIR
          mkfifo -m 0600 "$STROM_CONTROL_DIR/shutdown.fifo"
          # EXIT-trap rm of the FIFO dir is installed immediately so an
          # errexit abort during preHook still leaves /tmp tidy. The
          # signal-trap path (TERM/INT/HUP below) is a SEPARATE concern
          # (forwarding shutdown to bwrap mid-run).
          # The overlay unmount lives here too (not just postHook) so the
          # host fuse-overlayfs mount is released on EVERY exit path —
          # normal quit, errexit, and the TERM/INT/HUP trap (which exits
          # via this EXIT trap and never reaches postHook). Without it a
          # force-killed run would leak the mount until the next launch's
          # stale-sweep.
          #
          # We also reap the inner gamescope's per-launch private
          # XDG_RUNTIME_DIR (the strom-gs-* dir lib/gamescope.nix creates on
          # the host-shared /run bind). On a sway window-close of a proton
          # game the FIFO shutdown SIGKILLs the whole PID namespace, so the
          # gamescope-wrapper's own EXIT trap never runs and that dir leaks.
          # gamescope-wrapper appends its dir path to
          # $STROM_CONTROL_DIR/strom-gs-dirs; this host wrapper is never
          # killed by its own teardown (it does the killing), so its EXIT
          # trap is the reliable place to rm them.
          __strom_reap_gs_dirs() {
            [ -f "$STROM_CONTROL_DIR/strom-gs-dirs" ] || return 0
            while IFS= read -r _strom_gs_dir; do
              case "$_strom_gs_dir" in
                */strom-gs-*) rm -rf "$_strom_gs_dir" 2>/dev/null || true ;;
              esac
            done < "$STROM_CONTROL_DIR/strom-gs-dirs"
          }
          trap '${
            lib.optionalString (config.overlay != null) ''
              mountpoint -q "$STROM_CACHEDIR/overlay-merged" 2>/dev/null && fusermount3 -u "$STROM_CACHEDIR/overlay-merged" 2>/dev/null
            ''
          }${
            lib.optionalString (config.cleanupHook != "") ''
              ${config.cleanupHook}
            ''
          }__strom_reap_gs_dirs; rm -f "$STROM_CONTROL_DIR/strom-gs-dirs" "$STROM_CONTROL_DIR/shutdown.fifo" 2>/dev/null || true; rmdir "$STROM_CONTROL_DIR" 2>/dev/null || true' EXIT

          ${config.preHook}
          ${config.extraPreHook}
          read -ra _bwrap_extra <<< "''${BWRAP_ARGS:-}"
          ${lib.optionalString config.useStromRun ''
            # Common path: hand the whole tree to the native supervisor,
            # which forks bwrap into a child cgroup and tears it down with
            # cgroup.kill (atomic, from outside the pid ns) on game-exit /
            # signal / shutdown-FIFO / orphaning, then unmounts the overlay
            # and reaps the gamescope dirs. The inherited flock (fd 9) is
            # released when strom-run is reaped, so it cannot leak. The
            # EXIT trap installed above is discarded by exec (and serves as
            # the pre-exec safety net until then). Skipped when the n2n
            # overlay is active this launch ($N2N_SUPERNODE set): that path
            # needs slirp's fd-lifetime teardown, so it falls through to the
            # legacy bash supervision below.
            if [ -z "''${N2N_SUPERNODE:-}" ]; then
              exec strom-run ${stromRunArgs} -- \
                bwrap \
                ${bwrapArgs} \
                "''${_bwrap_extra[@]}" \
                -- \
                "${config.command}" "$@"
            fi
          ''}
          bwrap \
            ${
              concatMapStringsSep " \\\n  " shellEscape (
                # Drop the "$@" that wrapper.nix injects at mkOrder 1001;
                # we put it after ${command} below.
                lib.filter (a: a != "$@") (config.args or [ ])
              )
            } \
            "''${_bwrap_extra[@]}" \
            -- \
            "${config.command}" "$@" &
          BWRAP_PID=$!

          ${config.postLaunchHook}

          __strom_bwrap_cleanup() {
            if kill -0 "$BWRAP_PID" 2>/dev/null; then
              kill -KILL "$BWRAP_PID" 2>/dev/null || true
            fi
          }

          # Background FIFO reader. Blocks on `read` until something inside
          # the ns writes a line (or closes the fd via ns teardown). On
          # return, SIGKILL bwrap so the kernel atomically reaps the
          # namespace. Open the FIFO with `9<>` to avoid the open-for-read
          # blocking until a writer appears.
          (
            exec 9<>"$STROM_CONTROL_DIR/shutdown.fifo"
            read -r _ <&9 || true
            exec 9<&-
            __strom_bwrap_cleanup
          ) &
          STROM_FIFO_READER_PID=$!

          # Orphan watchdog. An abrupt teardown (e.g. `tmux kill-session`)
          # SIGHUPs gamescope but NOT this nested wrapper, which lives in a
          # child session: its INT/TERM/HUP traps never fire and it would sit
          # in the wait loop below holding the fuse-overlayfs mount + bwrap,
          # reparented to init. Detect being reparented to PID 1 (parent
          # died) and fire the shutdown FIFO so the normal teardown path
          # (FIFO reader -> SIGKILL bwrap -> wait breaks -> EXIT trap unmount)
          # runs. PPid is read from /proc/<pid>/status (unambiguous, unlike
          # awk-on-stat with a parenthesised comm). Only fire on a TRANSITION
          # to PPid 1, so a wrapper legitimately started by init/systemd
          # (PPid 1 from the start) is never falsely torn down.
          __strom_wrapper_pid=$$
          __strom_start_ppid=$(awk '/^PPid:/{print $2}' "/proc/$__strom_wrapper_pid/status" 2>/dev/null)
          (
            while kill -0 "$BWRAP_PID" 2>/dev/null; do
              __strom_now_ppid=$(awk '/^PPid:/{print $2}' "/proc/$__strom_wrapper_pid/status" 2>/dev/null)
              if [ "$__strom_now_ppid" = 1 ] && [ "$__strom_start_ppid" != 1 ]; then
                echo shutdown > "$STROM_CONTROL_DIR/shutdown.fifo" 2>/dev/null || true
                break
              fi
              sleep 2
            done
          ) &
          STROM_ORPHAN_WATCHDOG_PID=$!

          __strom_host_cleanup() {
            __strom_bwrap_cleanup
            ${config.cleanupHook}
            # Unblock the FIFO reader (in case bwrap exited without anyone
            # writing) so the wait below returns.
            if kill -0 "$STROM_FIFO_READER_PID" 2>/dev/null; then
              echo shutdown > "$STROM_CONTROL_DIR/shutdown.fifo" 2>/dev/null || true
              kill -TERM "$STROM_FIFO_READER_PID" 2>/dev/null || true
            fi
            # Stop the orphan watchdog (it self-exits when bwrap dies, but
            # reap it promptly so it does not linger up to one poll interval).
            kill -TERM "$STROM_ORPHAN_WATCHDOG_PID" 2>/dev/null || true
            __strom_reap_gs_dirs
            rm -f "$STROM_CONTROL_DIR/strom-gs-dirs" "$STROM_CONTROL_DIR/shutdown.fifo"
            rmdir "$STROM_CONTROL_DIR" 2>/dev/null || true
          }

          # Compose with any preHook-installed signal traps.
          __strom_prev_int=$(trap -p INT  | sed -n "s/^trap -- '\\(.*\\)' INT$/\\1/p"  | head -n1)
          __strom_prev_term=$(trap -p TERM | sed -n "s/^trap -- '\\(.*\\)' TERM$/\\1/p" | head -n1)
          __strom_prev_hup=$(trap -p HUP  | sed -n "s/^trap -- '\\(.*\\)' HUP$/\\1/p"  | head -n1)
          # shellcheck disable=SC2064 # expansion-now is intentional.
          trap "__strom_bwrap_cleanup; ''${__strom_prev_int:-true}"  INT
          # shellcheck disable=SC2064
          trap "__strom_bwrap_cleanup; ''${__strom_prev_term:-true}" TERM
          # shellcheck disable=SC2064
          trap "__strom_bwrap_cleanup; ''${__strom_prev_hup:-true}"  HUP

          while kill -0 "$BWRAP_PID" 2>/dev/null; do
            wait "$BWRAP_PID" 2>/dev/null && break
          done
          trap - INT TERM HUP
          __strom_host_cleanup
          wait "$STROM_FIFO_READER_PID" 2>/dev/null || true
          ${config.postHook}
        '';
    };
  };
}
