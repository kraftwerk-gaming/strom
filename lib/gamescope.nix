# Gamescope wrapperModule (raw module source).
#
# Wraps gamescope as a nested compositor that exec's an inner command.
# CLI shape: `gamescope [flags] -- $command "$@"`. The `--` separator
# delimits gamescope options from the program inside.
#
# Overrides outputs.wrapper directly so we can control argv ordering:
# wrapPackage's default template can't easily place `-- $command "$@"`
# AFTER all flags (config.flags via flags.nix lands at mkOrder 1000;
# the auto-injected "$@" lands at mkOrder 1001; there's no integer slot
# between them for `--`+command).
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  flagArgs = config.pkgs.lib.lists.concatLists (
    lib.mapAttrsToList (
      name: val:
      if val == null then
        [ ]
      else if val == true then
        [ name ]
      else
        [
          name
          (toString val)
        ]
    ) (lib.filterAttrs (_: v: v != null && v != false) config.gamescopeFlags)
  );
  shellEscape = arg: ''"${arg}"'';
in
{
  _class = "wrapper";

  options = {
    output-width = mkOption {
      type = types.nullOr types.int;
      default = null;
    };
    output-height = mkOption {
      type = types.nullOr types.int;
      default = null;
    };
    nested-width = mkOption {
      type = types.nullOr types.int;
      default = null;
    };
    nested-height = mkOption {
      type = types.nullOr types.int;
      default = null;
    };

    command = mkOption {
      type = types.either types.path types.str;
      description = "Inner program to run inside gamescope, after the `--` separator.";
    };

    # Internal: typed options + user-set `flags` get folded here. Rendered
    # verbatim into the wrapper before `--`.
    gamescopeFlags = mkOption {
      type = types.attrsOf (types.nullOr (types.either types.str types.bool));
      internal = true;
      default = { };
    };
  };

  config = {
    package = config.pkgs.gamescope;
    binName = lib.mkDefault "gamescope-wrapper";

    gamescopeFlags = {
      "--output-width" = if config.output-width != null then toString config.output-width else null;
      "--output-height" = if config.output-height != null then toString config.output-height else null;
      "--nested-width" = if config.nested-width != null then toString config.nested-width else null;
      "--nested-height" = if config.nested-height != null then toString config.nested-height else null;
      # NOTE: --virtual-connector-strategy=PerWindow was previously
      # set here to work around ValveSoftware/gamescope#1456 (the
      # CWaylandInputThread::ThreadFunc SingleApplication race during
      # proton startup, where the inner client briefly destroys and
      # recreates its toplevel — wineboot dialogs, splash screens, the
      # start.exe -> game.exe handoff — triggering an xdg_surface
      # protocol error that abort()s gamescope). That race turned out
      # to be driven by xalia's transient windows; disabling xalia via
      # PROTON_DISABLE_XALIA=1 (see lib/proton.nix) plus the EXIT-trap
      # process allowlist supersedes the PerWindow workaround.
      #
      # PerWindow had a nasty side-effect: it holds back mapping of
      # the outer xdg-toplevel until the inner xwayland client
      # creates *its* toplevel. Games with slow-to-create main
      # windows (Half-Life plays its Valve/Sierra intro videos
      # *before* hl.exe creates the main toplevel) end up invisible
      # on the host for several seconds — audio plays but no window
      # appears until the intro finishes. Dropping PerWindow here
      # restores immediate window-mapping; the SingleApplication
      # race stays suppressed by the xalia-disable fix.
    }
    // lib.mapAttrs (
      _: v:
      if v == false then
        null
      else if v == true then
        true
      else
        toString v
    ) config.flags;

    outputs.wrapper = config.pkgs.writeShellApplication {
      name = config.binName;
      runtimeInputs = [
        config.pkgs.gamescope
      ]
      ++ config.extraPackages;
      # GAMESCOPE_ARGS: runtime-injected gamescope flags, word-split and
      # spliced in just before `--`. Useful for per-machine knobs that
      # shouldn't bake into the derivation, e.g.
      #   GAMESCOPE_ARGS="--prefer-vk-device=8086:9b41" nix run .#half-life
      #
      # The screenshot sidecar (sourced below) probes for the nested
      # gamescope-* wayland socket and — when STROM_AGENT_DEBUG=1 —
      # captures PNGs every STROM_AGENT_DEBUG_INTERVAL seconds. It is a
      # no-op unless STROM_GAMEDIR is in scope (set by the strom
      # bwrap.preHook), so this stays harmless for non-strom callers.
      text = ''
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: ''export ${n}="${toString v}"'') config.env)}
        ${config.preHook}
        # strom: per-launch private XDG_RUNTIME_DIR so parallel gamescope
        # instances don't race on the shared gamescope-N wayland socket and
        # lockfile ("unable to lock lockfile .../gamescope-N.lock, maybe another
        # compositor is running"), and so the screenshot sidecar can't pick up
        # another session's frames. Each gamescope becomes gamescope-0 in its
        # own dir. The host wayland + audio sockets are symlinked through;
        # /dev/dri and /run/pipewire are bound separately and unaffected. We
        # keep `exec` below (no EXIT-trap cleanup), so leaked dirs -- tmpfs
        # symlink stubs -- are swept on the next launch after a day.
        _strom_priv=""
        _strom_xrd="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        _strom_ln() {
          if [ -e "$_strom_xrd/$1" ]; then
            ln -sfn "$_strom_xrd/$1" "$_strom_priv/$1" 2>/dev/null || true
          fi
        }
        if [ -d "$_strom_xrd" ] && [ -w "$_strom_xrd" ] \
          && _strom_priv="$(mktemp -d "$_strom_xrd/strom-gs-XXXXXX" 2>/dev/null)"; then
          find "$_strom_xrd" -maxdepth 1 -name 'strom-gs-*' -type d -mmin +1440 \
            -exec rm -rf {} + 2>/dev/null || true
          if [ -n "''${WAYLAND_DISPLAY:-}" ]; then
            _strom_ln "$WAYLAND_DISPLAY"
            _strom_ln "''${WAYLAND_DISPLAY}.lock"
          fi
          for _strom_s in pipewire-0 pipewire-0.lock pulse bus; do
            _strom_ln "$_strom_s"
          done
          export XDG_RUNTIME_DIR="$_strom_priv"
        fi
        ${builtins.readFile ./screenshot-sidecar.sh}
        read -ra _gamescope_extra <<< "''${GAMESCOPE_ARGS:-}"
        ${lib.optionalString (config.postHook == "") "exec"} gamescope \
          ${lib.concatMapStringsSep " \\\n  " shellEscape flagArgs} \
          "''${_gamescope_extra[@]}" \
          -- \
          "${config.command}" "$@"
        ${config.postHook}
      '';
    };
  };
}
