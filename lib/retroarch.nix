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

  coreOptionsCfg = config.pkgs.writeText "retroarch-core-options.cfg" (
    lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: ''${k} = "${v}"'') config.coreOptions)
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

    coreOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Core options written to retroarch-core-options.cfg (e.g. swanstation_GPU_ResolutionScale).";
    };

    romPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to the ROM file. May contain shell variables (e.g. $STROM_OVERLAY/foo.sfc).";
    };
  };

  config = {
    package = config.pkgs.retroarch;
    binName = lib.mkDefault "retroarch";

    # Isolate RetroArch's config per-game so it can't read/persist the user's
    # global ~/.config/retroarch (whose video_fullscreen=false was overriding
    # ours and leaving RetroArch windowed -> small centered inside gamescope).
    env = {
      XDG_CONFIG_HOME = "$STROM_GAMEDIR/config";
      # RetroArch links Qt for its desktop-menu UI; with WAYLAND_DISPLAY
      # unset (see preHook) a host QT_QPA_PLATFORM=wayland makes Qt's
      # platform init qFatal and take RetroArch down with it.
      QT_QPA_PLATFORM = "xcb";
    };

    # Write our config as RetroArch's MAIN config (at the XDG path above), with
    # save-on-exit off so nothing overrides it across runs.
    preHook = ''
      # Run RetroArch on gamescope's nested Xwayland, not its wayland display:
      # gamescope's --expose-wayland compositor lacks wp_viewporter and never
      # upscales a wayland client's fullscreen surface (1280x720 buffer stays
      # small and centered in the output), while its Xwayland path scales
      # fullscreen X11 windows to the output like every proton game.
      unset WAYLAND_DISPLAY
      mkdir -p "$STROM_GAMEDIR/saves" "$STROM_GAMEDIR/states" "$STROM_GAMEDIR/config/retroarch"
      {
        echo "savefile_directory = \"$STROM_GAMEDIR/saves\""
        echo "savestate_directory = \"$STROM_GAMEDIR/states\""
        echo "config_save_on_exit = \"false\""
        echo "global_core_options = \"true\""
        echo "log_verbosity = \"true\""
        echo "log_to_file = \"true\""
        echo "log_dir = \"$STROM_GAMEDIR/\""
        cat ${staticCfg}
      } > "$STROM_GAMEDIR/config/retroarch/retroarch.cfg"
      cat ${coreOptionsCfg} > "$STROM_GAMEDIR/config/retroarch/retroarch-core-options.cfg"
    '';

    args = [
      "-L"
      resolvedCore
      config.romPath
    ];
  };
}
