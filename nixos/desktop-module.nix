# NixOS module: install the strom web GUI and register the `strom://` URI
# scheme handler so the catalog's Play button can launch games.
#
# Usage in a flake:
#
#   {
#     imports = [ strom.nixosModules.strom-desktop ];
#     programs.strom-desktop.enable = true;
#   }
#
# This pulls `strom-gui` (run it to open the catalog) and `strom-launch` into
# the system profile and makes strom-launch.desktop the default handler for
# x-scheme-handler/strom.
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.strom-desktop;
  scripts = self.legacyPackages.${pkgs.system}.scripts;
in
{
  options.programs.strom-desktop = {
    enable = lib.mkEnableOption "the strom web GUI and strom:// launch handler";

    flake = lib.mkOption {
      type = lib.types.str;
      default = "github:kraftwerk-gaming/strom";
      description = ''
        Flake reference that `strom-launch` runs games from. Override to point
        at a local checkout (e.g. "path:/home/you/strom") for development.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      scripts.gui
      scripts.strom-launch
    ];

    # Make the launch handler the default for the strom:// scheme.
    xdg.mime.enable = true;
    xdg.mime.defaultApplications."x-scheme-handler/strom" = "strom-launch.desktop";

    # Point the handler (and GUI's launch hand-off) at the configured flake.
    environment.sessionVariables.STROM_FLAKE = cfg.flake;
  };
}
