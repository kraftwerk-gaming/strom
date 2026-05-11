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
  };

  config = {
    package = config.pkgs.bubblewrap;
    binName = lib.mkDefault "bwrap-wrapper";

    # Typed options feed into config.args at order 100 (early). Callers
    # can append further args with `bwrap.args = lib.mkAfter [ ... ];`
    # (order 1500). The wrapper template emits config.args verbatim.
    #
    # Order matters: bwrap applies mounts in argv order, and a `--tmpfs`
    # clobbers anything mounted under that path earlier. We emit
    # full-root mounts first (--ro-bind / /), then --tmpfs to wipe
    # selected dirs, then the targeted re-binds (--ro-bind-try,
    # --bind, --bind-try, --dev-bind) which now establish mountpoints
    # inside the tmpfs'd dirs.
    args = lib.mkOrder 100 (
      optionals config.unshare-pid [ "--unshare-pid" ]
      ++ optionals config.unshare-net [ "--unshare-net" ]
      ++ optionals config.share-net [ "--share-net" ]
      ++ optionals config.die-with-parent [ "--die-with-parent" ]
      ++ renderPairs "--ro-bind" config.ro-bind
      ++ renderSingles "--tmpfs" config.tmpfs
      ++ renderSingles "--proc" config.proc
      ++ renderPairs "--dev-bind" config.dev-bind
      ++ renderPairs "--ro-bind-try" config.ro-bind-try
      ++ renderPairs "--bind" config.bind
      ++ renderPairs "--bind-try" config.bind-try
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
      text = ''
        ${lib.concatStringsSep "\n" (mapAttrsToList (n: v: ''export ${n}="${toString v}"'') config.env)}
        ${config.preHook}
        bwrap \
          ${
            concatMapStringsSep " \\\n  " shellEscape (
              # Drop the "$@" that wrapper.nix injects at mkOrder 1001 —
              # we put it after ${command} below, not in bwrap's argv.
              lib.filter (a: a != "$@") (config.args or [ ])
            )
          } \
          -- \
          "${config.command}" "$@" &
        BWRAP_PID=$!
        wait $BWRAP_PID || true
        ${config.postHook}
      '';
    };
  };
}
