# General-purpose RetroArch wrapperModule.
{ wlib }:

wlib.wrapModule (
  {
    config,
    lib,
    ...
  }:
  let
    corePaths = builtins.concatMap (
      core:
      map (f: "${core}/lib/retroarch/cores/${f}") (
        builtins.filter (f: lib.hasSuffix ".so" f) (
          builtins.attrNames (builtins.readDir "${core}/lib/retroarch/cores")
        )
      )
    ) config.cores;
  in
  {
    _class = "wrapper";

    options = {
      cores = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Libretro cores to include.";
      };

      core = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if builtins.length corePaths == 1 then builtins.head corePaths else null;
        defaultText = "Auto-selected when exactly one core is provided.";
        description = "Path to the libretro core .so file to load.";
      };

      settings = lib.mkOption {
        type = lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.str;
          options = {
            system_directory = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Path to BIOS/system files directory.";
            };
            input_autodetect_enable = lib.mkOption {
              type = lib.types.str;
              default = "true";
              description = "Enable automatic gamepad detection.";
            };
            input_joypad_driver = lib.mkOption {
              type = lib.types.str;
              default = "sdl2";
              description = "Joypad input driver.";
            };
            pause_nonactive = lib.mkOption {
              type = lib.types.str;
              default = "false";
              description = "Pause when window loses focus.";
            };
            video_driver = lib.mkOption {
              type = lib.types.str;
              default = "vulkan";
              description = "Video driver.";
            };
            video_fullscreen = lib.mkOption {
              type = lib.types.str;
              default = "false";
              description = "Start in fullscreen.";
            };
            video_windowed_fullscreen = lib.mkOption {
              type = lib.types.str;
              default = "false";
              description = "Use windowed fullscreen.";
            };
          };
        };
        default = { };
        description = "RetroArch configuration settings.";
      };

      "retroarch.cfg" = lib.mkOption {
        type = wlib.types.file config.pkgs;
        description = "RetroArch configuration file.";
        default.content = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (k: v: ''${k} = "${v}"'') (lib.filterAttrs (_: v: v != "") config.settings)
        );
      };
    };

    config = {
      package = config.pkgs.retroarch.withCores (_: config.cores);
      flags = {
        "--appendconfig" = toString config."retroarch.cfg".path;
      }
      // lib.optionalAttrs (config.core != null) {
        "-L" = config.core;
      };
    };
  }
)
