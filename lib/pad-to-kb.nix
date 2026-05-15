# pad-to-kb wrapperModule (raw module source).
#
# Wraps evsieve to translate gamepad / joystick evdev events into a
# synthesized virtual keyboard (via uinput). Designed to be launched
# in the BACKGROUND from a game wrapper's outermost (host-side) hook,
# so the virtual device exists before bwrap binds /dev/input/ into the
# sandbox. Cleanup is handled by a SIGTERM from the calling preHook's
# trap chain.
#
# Host requirements: write access to /dev/uinput (NixOS default udev
# rules + membership in `input` group are sufficient).
#
# Architectural note: the launcher fragment in mk-game.nix does the
# evdev device glob-expansion at runtime, so this module bakes only
# the bindings + output flags into argv. The wrapped binary is exposed
# as `mappingArgs` (rendered evsieve argv) plus `package`; the
# launcher composes them with the expanded `--input` flags into a
# full invocation.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;

  bindingArgs =
    let
      verb = if config.passthrough then "--copy" else "--map";
      mapOne = src: dst: [
        verb
        src
        dst
      ];
    in
    lib.concatLists (lib.mapAttrsToList mapOne config.bindings);
in
{
  _class = "wrapper";

  options = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to launch the evsieve gamepad-to-keyboard remapper
        alongside the game. When false, the wrapperModule is inert
        and nothing about the launch flow changes.
      '';
    };

    inputDevices = mkOption {
      type = types.listOf types.str;
      default = [ "/dev/input/by-id/*-event-joystick" ];
      description = ''
        Shell glob patterns (expanded at launch time) or absolute
        paths under /dev/input that evsieve reads events from. The
        default picks up every connected gamepad via the by-id
        symlinks udev creates. evsieve's `persist=reopen` is applied
        so hot-plug works.
      '';
    };

    bindings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = lib.literalExpression ''
        {
          "btn:south" = "key:enter";
          "btn:east" = "key:esc";
          "abs:hat0x:-1" = "key:left";
          "abs:x:-32768..-16384" = "key:left";
        }
      '';
      description = ''
        Attrset of source-event -> destination-event in evsieve's
        native DSL. See evsieve(1) for the full event grammar.
      '';
    };

    passthrough = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When true, source events also reach the game in their original
        form (via `--copy`), so the pad acts as BOTH a keyboard AND a
        controller. When false, source events are consumed (`--map`).
      '';
    };

    virtualName = mkOption {
      type = types.str;
      default = "strom-virtual-keyboard";
      description = ''
        `name=` for evsieve's `--output`. Shown in
        /proc/bus/input/devices.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra raw evsieve arguments, placed between the bindings and
        the `--output` block. Use for additional `--copy`/`--map`
        clauses that need multi-destination syntax (chords),
        `--hook`, `--print`, ...
      '';
    };

    package = mkOption {
      type = types.package;
      default = config.pkgs.evsieve;
      defaultText = lib.literalExpression "pkgs.evsieve";
    };

    # Rendered evsieve argv (bindings + extraArgs). The launcher
    # fragment prepends the runtime-expanded --input list and
    # appends the --output block (which embeds the runtime
    # $STROM_PAD_TO_KB_LINK path), then execs evsieve.
    mappingArgs = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      internal = true;
      default = bindingArgs ++ config.extraArgs;
    };
  };

  config = {
    # `package` is the evsieve binary. The wrappers base requires
    # binName; the launcher invokes evsieve directly with the
    # runtime-built argv, so `outputs.wrapper` is unused.
    binName = lib.mkDefault "evsieve";
  };
}
