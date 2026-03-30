{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config;

  prepareGameDir = pkgs.callPackage ./prepare-game-dir.nix {
    gameFiles = cfg._gameData;
    copyGlobs = cfg.copyGlobs;
  };

  proton =
    if cfg.patchedProton then
      pkgs.callPackage ./patched-proton.nix { }
    else
      pkgs.proton-ge-bin.steamcompattool;

  wrapper = pkgs.writeShellScript "${cfg.name}-wrapper" ''
    set -euo pipefail

    GAMEDIR="''${HOME:-.}/.strom/${cfg.name}"
    COMPATDATA="$GAMEDIR/compatdata"
    mkdir -p "$GAMEDIR" "$COMPATDATA"

    ${prepareGameDir} "$GAMEDIR"

    ${lib.optionalString (cfg.runtime == "proton") ''
      export STEAM_COMPAT_DATA_PATH="$COMPATDATA"
      export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
      export STEAM_COMPAT_APP_ID="0"
    ''}

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") cfg.env
    )}

    cd "$GAMEDIR"
    ${cfg.runScript}
  '';
in
{
  options = with lib; {
    name = mkOption {
      type = types.str;
      description = "Game name (used for ~/.strom/<name>)";
    };

    src = mkOption {
      type = types.package;
      description = "Source archive/fetchurl";
    };

    buildScript = mkOption {
      type = types.str;
      default = "";
      description = "Shell script to extract/prepare game data. Runs in nix build. Has $src and $out.";
    };

    nativeBuildInputs = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Build-time dependencies for buildScript";
    };

    runScript = mkOption {
      type = types.str;
      description = "Shell script to launch the game. Has $GAMEDIR, $COMPATDATA.";
    };

    copyGlobs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Glob patterns for files/dirs to copy instead of symlink. Trailing / for dirs.";
    };

    env = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Environment variables to set before launching";
    };

    runtime = mkOption {
      type = types.enum [
        "proton"
        "wine"
        "dosbox"
        "dosbox-x"
        "native"
        "ruffle"
        "custom"
      ];
      default = "custom";
      description = "Runtime environment type";
    };

    patchedProton = mkOption {
      type = types.bool;
      default = true;
      description = "Use patched Proton with symlinked prefix (saves ~500MB per game)";
    };

    targetPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = _: [ ];
      description = "FHS environment packages (for buildFHSEnv)";
    };

    extraBwrapArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra bwrap arguments for FHS environment";
    };

    meta = mkOption {
      type = types.attrs;
      default = { };
      description = "Derivation metadata";
    };

    # Internal options
    _gameData = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
    };
    _build = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
    };
  };

  config = {
    _gameData =
      pkgs.runCommandLocal "${cfg.name}-data"
        {
          nativeBuildInputs = cfg.nativeBuildInputs;
          src = cfg.src;
        }
        (
          if cfg.buildScript != "" then
            cfg.buildScript
          else
            ''
              mkdir -p $out
              cp -r $src/. $out/ || cp $src $out/
            ''
        );

    _build =
      if cfg.runtime == "proton" then
        pkgs.buildFHSEnv {
          name = cfg.name;
          runScript = wrapper;
          targetPkgs =
            p:
            [
              p.freetype
              p.glibc
              p.gamescope
              p.python3
              p.mesa
              p.vulkan-loader
              p.libGL
              p.libx11
              p.libxext
              p.libxcb
              p.libxcursor
              p.libxrandr
              p.libxi
              p.libxfixes
              p.libxrender
              p.libxcomposite
              p.libxinerama
              p.libxxf86vm
              p.alsa-lib
              p.libpulseaudio
              p.openal
              p.systemd
              (pkgs.callPackage ./sdl2-real.nix { })
              p.pkgsi686Linux.freetype
              p.pkgsi686Linux.glibc
              p.pkgsi686Linux.glib
              p.pkgsi686Linux.libx11
              p.pkgsi686Linux.libxext
              p.pkgsi686Linux.libxcb
              p.pkgsi686Linux.libxcursor
              p.pkgsi686Linux.libxrandr
              p.pkgsi686Linux.libxi
              p.pkgsi686Linux.libxfixes
              p.pkgsi686Linux.libxrender
              p.pkgsi686Linux.libxcomposite
              p.pkgsi686Linux.libxinerama
              p.pkgsi686Linux.libxxf86vm
              p.pkgsi686Linux.libGL
              p.pkgsi686Linux.mesa
              p.pkgsi686Linux.vulkan-loader
              p.pkgsi686Linux.openal
              p.pkgsi686Linux.alsa-lib
              p.pkgsi686Linux.libpulseaudio
            ]
            ++ (cfg.targetPkgs p);
          extraBwrapArgs = [
            "--ro-bind /sys /sys"
            "--bind /run /run"
          ]
          ++ cfg.extraBwrapArgs;
          inherit (cfg) meta;
        }
      else if cfg.runtime == "native" then
        pkgs.writeShellApplication {
          inherit (cfg) name meta;
          runtimeInputs = [ pkgs.gamescope ];
          text = ''
            GAMEDIR="''${HOME:-.}/.strom/${cfg.name}"
            mkdir -p "$GAMEDIR"
            ${prepareGameDir} "$GAMEDIR"
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") cfg.env
            )}
            cd "$GAMEDIR"
            ${cfg.runScript}
          '';
        }
      else
        # custom: just use the FHS env with the wrapper
        pkgs.buildFHSEnv {
          name = cfg.name;
          runScript = wrapper;
          targetPkgs = cfg.targetPkgs;
          extraBwrapArgs = cfg.extraBwrapArgs;
          inherit (cfg) meta;
        };
  };
}
