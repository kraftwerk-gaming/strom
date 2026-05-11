# retroarch wrapperModule (raw module source).
#
# Wraps RetroArch with a libretro core and a composed retroarch.cfg.
# The wrapped binary IS retroarch; the rom path is a typed option
# (romPath) appended as a positional argument.
#
# Usage as a sub-option submodule:
#   lib.types.submoduleWith {
#     specialArgs = { inherit wlib; };
#     modules = [ wlib.modules.wrapper wlib.modules.meta (import ./retroarch.nix) ];
#   }
{ config, lib, ... }:
let
  # Core auto-pick: scan each provided core derivation for *.so under
  # lib/retroarch/cores/. If exactly one match across all cores, use it.
  # Caller can set retroarch.core explicitly to skip.
  corePaths = lib.concatMap (
    core:
    map (f: "${core}/lib/retroarch/cores/${f}") (
      lib.filter (lib.hasSuffix ".so") (lib.attrNames (builtins.readDir "${core}/lib/retroarch/cores"))
    )
  ) config.cores;

  resolvedCore =
    if config.core != null then
      config.core
    else if lib.length corePaths == 1 then
      lib.head corePaths
    else
      throw "retroarch.cores must contain exactly one core .so, or set retroarch.core explicitly";

  staticCfg = config.pkgs.writeText "retroarch.cfg" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: ''${k} = "${v}"'') (lib.filterAttrs (_: v: v != "") config.settings)
    )
  );
in
{
  _class = "wrapper";

  options = {
    cores = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "List of libretro core packages. One .so across all cores auto-picked.";
    };

    core = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Explicit core .so path. If null, auto-picked from cores.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Static retroarch.cfg settings: { key = value; }. Empty values skipped.";
    };

    romPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to the ROM file. May contain shell variables (e.g. $STROM_OVERLAY/foo.sfc).";
    };
  };

  config = {
    package = config.pkgs.retroarch;
    binName = lib.mkDefault "retroarch";

    # Compose dynamic save/state paths into the runtime cfg. Dynamic paths
    # depend on $STROM_GAMEDIR (only known at run time); the static fragment
    # is from the nix store.
    preHook = ''
      mkdir -p "$STROM_GAMEDIR/saves" "$STROM_GAMEDIR/states"
      {
        echo "savefile_directory = \"$STROM_GAMEDIR/saves\""
        echo "savestate_directory = \"$STROM_GAMEDIR/states\""
        cat ${staticCfg}
      } > "$STROM_CACHEDIR/retroarch.cfg"
    '';

    args = [
      "-L"
      resolvedCore
      "--appendconfig"
      "$STROM_CACHEDIR/retroarch.cfg"
      config.romPath
    ];
  };
}
