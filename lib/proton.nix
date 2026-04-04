# Proton wrapperModule.
#
# Wraps Proton with STEAM_COMPAT_* env vars and wineserver cleanup.
# The wrapped binary runs: proton waitforexitandrun "$@"
# then cleans up wineserver and kills the process group.
{ wlib }:

wlib.wrapModule (
  { config, lib, ... }:
  {
    _class = "wrapper";

    options = {
      compatDataPath = lib.mkOption {
        type = lib.types.str;
        description = "Path for Proton compatibility data. May contain shell variables like $HOME.";
      };
    };

    config = {
      package = lib.mkDefault (config.pkgs.callPackage ../pkgs/proton.nix { });
      exePath = "${config.package}/proton";
      binName = "proton";

      env = {
        STEAM_COMPAT_DATA_PATH = config.compatDataPath;
        STEAM_COMPAT_CLIENT_INSTALL_PATH = config.compatDataPath;
        STEAM_COMPAT_APP_ID = "0";
      };

      extraPackages = [ config.pkgs.python3 ];

      preHook = ''
        mkdir -p "${config.compatDataPath}"
      '';

      args = [ "waitforexitandrun" ];

      postHook = ''
        ${config.package}/files/bin/wineserver -k 2>/dev/null || true
        ${config.package}/files/bin/wineserver -w 2>/dev/null || true
        kill -9 0 2>/dev/null
      '';


    };
  }
)
