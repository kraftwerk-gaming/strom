# bwrap wrapperModule (raw module source).
#
# Wraps a target command inside a bubblewrap sandbox. The wrapped binary
# is bwrap itself; the target lives in `config.command` and is appended
# as an argv tail after `bwrap [flags] --`.
#
# Typed options compose into `config.args` via lib.mkOrder, so callers can
# append further args with `bwrap.args = lib.mkAfter [ ... ];`. Values may
# contain shell-variable references (e.g. "$HOME", "$STROM_GAMEDIR") that
# expand at wrapper-runtime when bash builds bwrap's argv.
#
# The wrapper template launches bwrap in the background and captures
# $BWRAP_PID, so a caller's preHook can install
# `trap 'kill -TERM $BWRAP_PID; ...' INT TERM EXIT` for signal-driven
# cleanup (used by the strom-outer setup to fusermount-unmount the
# overlay on signal).
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
in
{
  _class = "wrapper";

  options = {
    command = mkOption {
      type = types.either types.path types.str;
      description = ''
        The target program to exec inside the sandbox. May contain shell
        variable references (e.g. $STROM_OVERLAY/foo).
      '';
    };

    unshare-pid = mkOption {
      type = types.bool;
      default = false;
      description = "Pass --unshare-pid (new PID namespace; namespace teardown kills children on bwrap exit).";
    };
    unshare-net = mkOption {
      type = types.bool;
      default = false;
      description = "Pass --unshare-net.";
    };
    share-net = mkOption {
      type = types.bool;
      default = false;
      description = "Pass --share-net (keep host network namespace).";
    };
    die-with-parent = mkOption {
      type = types.bool;
      default = true;
      description = "Pass --die-with-parent.";
    };

    ro-bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Read-only bind mounts: { dest = src; }.";
    };
    ro-bind-try = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Read-only bind mounts; silent on missing src.";
    };
    bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Read-write bind mounts: { dest = src; }.";
    };
    bind-try = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Read-write bind mounts; silent on missing src.";
    };
    dev-bind = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Device bind mounts (allows /dev access).";
    };
    tmpfs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Paths to mount as tmpfs inside the sandbox.";
    };
    proc = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Paths to mount as procfs.";
    };
    chdir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Working directory inside the sandbox.";
    };
    setenv = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Env vars to set inside the sandbox: { NAME = VALUE; }.";
    };
    chmod = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Mode bits for paths: { path = mode; } -> --chmod mode path.";
    };
    extraPreHook = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Additional shell commands to run before bwrap launches. Concatenates
        across module definitions (types.lines), unlike the upstream `preHook`
        (types.str) which only allows a single definition. Use this to extend
        the strom-outer preHook from a game module — e.g. to write a file
        that gets referenced by an extra BWRAP_ARGS bind.
      '';
    };
  };

  config = {
    package = config.pkgs.bubblewrap;
    binName = lib.mkDefault "bwrap-wrapper";

    # Typed options feed into config.args at order 100 (early). Callers
    # can append further args with `bwrap.args = lib.mkAfter [ ... ];`
    # (order 1500). The wrapper template emits config.args verbatim.
    #
    # Order matters: bwrap applies mounts in argv order, and any mount
    # at path P overlays anything previously mounted under P. The order
    # we want:
    #   1. --ro-bind / /            base ro view of host
    #   2. --bind                   RW re-bind specific parent dirs
    #                               (e.g. /tmp /tmp so /tmp is writable)
    #   3. --tmpfs                  carve sandbox-owned dirs out of (1)/(2)
    #                               (e.g. tmpfs /tmp/.X11-unix inside RW /tmp)
    #   4. --ro-bind-try, --bind-try  overlay specific host paths INSIDE
    #                               the tmpfs'd dirs (e.g. host X11 sockets,
    #                               $HOME/.cache/umu inside tmpfs $HOME)
    #   5. --proc, --dev-bind       /proc, /dev (independent paths)
    #
    # Crucially --bind comes BEFORE --tmpfs: re-binding a parent dir
    # after tmpfs'ing one of its children would wipe the tmpfs.
    args = lib.mkOrder 100 (
      optionals config.unshare-pid [ "--unshare-pid" ]
      ++ optionals config.unshare-net [ "--unshare-net" ]
      ++ optionals config.share-net [ "--share-net" ]
      ++ optionals config.die-with-parent [ "--die-with-parent" ]
      ++ renderPairs "--ro-bind" config.ro-bind
      ++ renderPairs "--bind" config.bind
      ++ renderSingles "--tmpfs" config.tmpfs
      ++ renderPairs "--ro-bind-try" config.ro-bind-try
      ++ renderPairs "--bind-try" config.bind-try
      ++ renderSingles "--proc" config.proc
      ++ renderPairs "--dev-bind" config.dev-bind
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

    # Override outputs.wrapper: bwrap launches in the background with
    # $BWRAP_PID captured so a caller's preHook trap can forward signals.
    outputs.wrapper = config.pkgs.writeShellApplication {
      name = config.binName;
      runtimeInputs = [ config.pkgs.bubblewrap ] ++ config.extraPackages;
      # BWRAP_ARGS: runtime-injected bwrap flags, word-split and spliced
      # in just before `--`. Useful for ad-hoc binds during debugging,
      # e.g. BWRAP_ARGS="--bind /home/me/saves /home/me/saves".
      #
      # Signal-driven teardown: the host WM can close the outer gamescope
      # window without the inner game cooperating (gamescope upstream
      # has known hangs when wineserver lingers — see
      # ValveSoftware/gamescope#1615). To make WM-close reliable we
      # install a TERM/INT/HUP trap that sends polite SIGTERM to bwrap
      # then escalates to SIGKILL after ~3s. Combined with bwrap's
      # --die-with-parent + --unshare-pid this guarantees the entire
      # PID namespace (gamescope + wineserver + game) tears down.
      # `wait` runs in a slice loop so the trap fires immediately on
      # signal delivery instead of being deferred until bwrap exits.
      text = ''
        ${lib.concatStringsSep "\n" (mapAttrsToList (n: v: ''export ${n}="${toString v}"'') config.env)}
        ${config.preHook}
        ${config.extraPreHook}
        read -ra _bwrap_extra <<< "''${BWRAP_ARGS:-}"
        bwrap \
          ${
            concatMapStringsSep " \\\n  " shellEscape (
              # Drop the "$@" that wrapper.nix injects at mkOrder 1001 —
              # we put it after ${command} below, not in bwrap's argv.
              lib.filter (a: a != "$@") (config.args or [ ])
            )
          } \
          "''${_bwrap_extra[@]}" \
          -- \
          "${config.command}" "$@" &
        BWRAP_PID=$!

        __strom_bwrap_cleanup() {
          if kill -0 "$BWRAP_PID" 2>/dev/null; then
            kill -TERM "$BWRAP_PID" 2>/dev/null || true
            for _ in $(seq 1 30); do
              kill -0 "$BWRAP_PID" 2>/dev/null || break
              sleep 0.1
            done
            kill -KILL "$BWRAP_PID" 2>/dev/null || true
          fi
        }
        # Compose with any preHook-installed INT/TERM/HUP traps so e.g.
        # mk-game's `fusermount -uz` cleanup still runs. EXIT traps fire
        # too once we return and the script exits.
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
        ${config.postHook}
      '';
    };
  };
}
