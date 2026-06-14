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

  # gamescope's xwm channel emits two benign warnings that spam stderr
  # ("got the same buffer committed twice, ignoring." on duplicate frame
  # commits, and "No upscale images free!"). Both are handled internally
  # and harmless. Raise the xwm log channel to `error` via gamescope's own
  # Lua convar API so those warnings are dropped while xwm *errors* still
  # print. Loaded by pointing GAMESCOPE_SCRIPT_PATH at this dir below
  # (alongside the bundled default scripts).
  quietXwmScript = config.pkgs.writeTextDir "zz-strom-quiet-xwm.lua" ''
    local c = gamescope.convars.log_xwm
    if c then c:call("error") end
  '';
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
        # gamescope's nested Xwayland does NOT inherit the host seat's xkb
        # layout (gamescope#203): it builds its keymap from XKB_DEFAULT_LAYOUT
        # at seat init, and `setxkbmap` on the outer X never reaches the nest.
        # Left unset, letter keys don't translate to WM_CHAR under Wine, so any
        # typing path (name entry / chat / dev console / word-games like
        # cryptmaster) silently breaks while digits + mouse still work. Default
        # the nest to a sane keymap here. These exports PRECEDE config.env, so a
        # per-game `gamescope.env.XKB_DEFAULT_LAYOUT` still wins; the `:-`
        # defaults also respect an externally-set value (e.g. a non-US user
        # running `XKB_DEFAULT_LAYOUT=de nix run .#game`). VARIANT defaults empty
        # — a non-empty variant the nest can't build segfaults its Xwayland.
        export XKB_DEFAULT_LAYOUT="''${XKB_DEFAULT_LAYOUT:-us}"
        export XKB_DEFAULT_VARIANT="''${XKB_DEFAULT_VARIANT:-}"
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: ''export ${n}="${toString v}"'') config.env)}
        ${config.preHook}
        # strom: per-launch private XDG_RUNTIME_DIR so parallel gamescope
        # instances don't race on the shared gamescope-N wayland socket and
        # lockfile ("unable to lock lockfile .../gamescope-N.lock, maybe another
        # compositor is running"), and so the screenshot sidecar can't pick up
        # another session's frames. Each gamescope becomes gamescope-0 in its
        # own dir. The host wayland + audio sockets are symlinked through;
        # /dev/dri and /run/pipewire are bound separately and unaffected.
        # Cleaned up on exit: we set an EXIT trap (the screenshot sidecar
        # chains it) and run gamescope WITHOUT exec so the trap can fire.
        # On a sway window-close of a PROTON game the EXIT trap is NOT
        # enough: gamescope exits, but before this bash returns to run the
        # trap the proton-wrapper's FIFO shutdown fires and the host
        # bwrap-wrapper SIGKILLs the bwrap PID, tearing the whole PID
        # namespace (this bash included) down with an uncatchable SIGKILL —
        # so the trap never runs and the strom-gs dir leaks. The dir lives
        # on the host-shared /run bind, so we additionally record its path
        # into the host-side control dir (bound at /tmp/.strom-control via
        # STROM_CONTROL_FIFO); the host bwrap-wrapper — the one process the
        # teardown never kills, since it does the killing — rms it from its
        # own EXIT trap. The 1-day sweep only backstops the rare case where
        # even that path is missed (e.g. a SIGKILL of the host wrapper).
        _strom_priv=""
        _strom_xrd="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        _strom_ln() {
          if [ -e "$_strom_xrd/$1" ]; then
            ln -sfn "$_strom_xrd/$1" "$_strom_priv/$1" 2>/dev/null || true
          fi
        }
        if [ -d "$_strom_xrd" ] && [ -w "$_strom_xrd" ] \
          && _strom_priv="$(mktemp -d "$_strom_xrd/strom-gs-XXXXXX" 2>/dev/null)"; then
          trap 'rm -rf "$_strom_priv"' EXIT
          _strom_ctl="''${STROM_CONTROL_FIFO%/*}"
          if [ -n "''${STROM_CONTROL_FIFO:-}" ] && [ -d "$_strom_ctl" ]; then
            printf '%s\n' "$_strom_priv" >> "$_strom_ctl/strom-gs-dirs" 2>/dev/null || true
          fi
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
        # Load gamescope's bundled scripts plus our xwm-quiet convar script.
        # Setting GAMESCOPE_SCRIPT_PATH skips the compiled-in default folder,
        # so re-list it here to keep the stock scripts loading.
        export GAMESCOPE_SCRIPT_PATH="${config.pkgs.gamescope}/share/gamescope/scripts:${quietXwmScript}''${GAMESCOPE_SCRIPT_PATH:+:$GAMESCOPE_SCRIPT_PATH}"
        read -ra _gamescope_extra <<< "''${GAMESCOPE_ARGS:-}"
        gamescope \
          ${lib.concatMapStringsSep " \\\n  " shellEscape flagArgs} \
          "''${_gamescope_extra[@]}" \
          -- \
          "${config.command}" "$@"
        ${config.postHook}
      '';
    };
  };
}
