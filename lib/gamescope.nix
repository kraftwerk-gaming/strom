# Gamescope wrapperModule.
#
# Wraps the gamescope binary with configurable flags.
# The wrapped binary runs: gamescope [flags] "$@"
# The "--" separator and GAMESCOPE_PARAMS injection happen in mk-game.nix.
{ wlib }:

wlib.wrapModule (
  { config, lib, ... }:
  {
    _class = "wrapper";

    options = {
      output-width = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Output width. Null lets gamescope pick.";
      };

      output-height = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Output height. Null lets gamescope pick.";
      };

      nested-width = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Game render width. Null lets gamescope pick.";
      };

      nested-height = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Game render height. Null lets gamescope pick.";
      };
    };

    config = {
      package = config.pkgs.gamescope;
      flags = {
        "--output-width" = if config.output-width != null then toString config.output-width else false;
        "--output-height" = if config.output-height != null then toString config.output-height else false;
        "--nested-width" = if config.nested-width != null then toString config.nested-width else false;
        "--nested-height" = if config.nested-height != null then toString config.nested-height else false;
      };
      # NOTE: the "--" separator is added by mk-game.nix launch commands,
      # not here, so that GAMESCOPE_PARAMS can be injected before it.
    };
  }
)
