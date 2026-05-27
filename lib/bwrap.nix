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
            lowerDir = mkOption { type = types.str; };
            upperDir = mkOption { type = types.str; };
            workDir = mkOption { type = types.str; };
            dest = mkOption { type = types.str; };
          };
        }
      );
      default = null;
      description = ''
        Overlay mount via --overlay-src/--overlay. lowerDir is the
        nix-store game data; upperDir takes writes; mounted at dest.
      '';
    };

    extraPreHook = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra shell commands before bwrap launches. types.lines, so
        multiple definitions concatenate (unlike upstream preHook).
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
      ++ optionals (config.overlay != null) [
        "--overlay-src"
        config.overlay.lowerDir
        "--overlay"
        config.overlay.upperDir
        config.overlay.workDir
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
      runtimeInputs = [ config.pkgs.bubblewrap ] ++ config.extraPackages;
      text = ''
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
        trap 'rm -f "$STROM_CONTROL_DIR/shutdown.fifo" 2>/dev/null || true; rmdir "$STROM_CONTROL_DIR" 2>/dev/null || true' EXIT

        ${config.preHook}
        ${config.extraPreHook}
        read -ra _bwrap_extra <<< "''${BWRAP_ARGS:-}"
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

        __strom_host_cleanup() {
          __strom_bwrap_cleanup
          # Unblock the FIFO reader (in case bwrap exited without anyone
          # writing) so the wait below returns.
          if kill -0 "$STROM_FIFO_READER_PID" 2>/dev/null; then
            echo shutdown > "$STROM_CONTROL_DIR/shutdown.fifo" 2>/dev/null || true
            kill -TERM "$STROM_FIFO_READER_PID" 2>/dev/null || true
          fi
          rm -f "$STROM_CONTROL_DIR/shutdown.fifo"
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
