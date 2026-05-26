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
      # Work around ValveSoftware/gamescope#1456: in the default
      # SingleApplication virtual-connector mode the wayland backend
      # races with the host compositor when the inner client briefly
      # destroys and recreates its toplevel window — a common pattern
      # during proton startup (wineboot dialogs, splash screens, the
      # start.exe -> game.exe handoff). The host compositor (sway/
      # wlroots) raises an xdg_surface protocol error, gamescope's
      # input thread fails wl_display_get_fd, and the compositor
      # abort()s in CWaylandInputThread::ThreadFunc. PerWindow
      # virtual-connector strategy creates a fresh wl_surface per
      # toplevel instead of reusing one, avoiding the unconfigured-
      # buffer protocol error. Games can override with
      # gamescope.flags."--virtual-connector-strategy" = null.
      "--virtual-connector-strategy" = "PerWindow";
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
