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
      package = config.pkgs.callPackage ../pkgs/proton.nix { };
      exePath = "${config.package}/proton";
      binName = "proton";

      env = {
        STEAM_COMPAT_DATA_PATH = config.compatDataPath;
        STEAM_COMPAT_CLIENT_INSTALL_PATH = config.compatDataPath;
        STEAM_COMPAT_APP_ID = "0";
      };

      extraPackages = [ config.pkgs.python3 ];

      # Proton's lsteamclient hardcodes $HOME/.steam/sdk{32,64}/steamclient.so
      # and asserts on dlopen failure. Symlink a stub so games run without
      # requiring a host Steam install.
      preHook =
        let
          stub = config.pkgs.callPackage ../pkgs/steamclient-stub { };
        in
        ''
          mkdir -p "${config.compatDataPath}"
          mkdir -p "''${HOME:-.}/.steam/sdk32" "''${HOME:-.}/.steam/sdk64"
          ln -sf ${stub}/sdk32/steamclient.so "''${HOME:-.}/.steam/sdk32/steamclient.so"
          ln -sf ${stub}/sdk64/steamclient.so "''${HOME:-.}/.steam/sdk64/steamclient.so"
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
