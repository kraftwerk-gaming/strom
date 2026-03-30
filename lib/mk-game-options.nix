{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config;

  protonRun = pkgs.writeShellScript "proton-run" ''
    python3 "${proton}/proton" waitforexitandrun "$@"
    ${proton}/files/bin/wineserver -k 2>/dev/null || true
    ${proton}/files/bin/wineserver -w 2>/dev/null || true
    kill -9 0 2>/dev/null
  '';

  patchedFuseOverlayfs = pkgs.callPackage ./fuse-overlayfs-patched.nix { };

  prepareGameDir = pkgs.callPackage ./prepare-game-dir.nix {
    fuse-overlayfs = patchedFuseOverlayfs;
    gameFiles = cfg._gameData;
    copyGlobs = cfg.copyGlobs;
  };

  proton =
    if cfg.patchedProton then
      pkgs.callPackage ./patched-proton.nix { }
    else
      pkgs.proton-ge-bin.steamcompattool;

  # Runs inside FHS/bwrap
  innerWrapper = pkgs.writeShellScript "${cfg.name}-inner" ''
    set -euo pipefail

    GAMEDIR="$STROM_OVERLAY"
    COMPATDATA="''${HOME:-.}/.strom/.compatdata/${cfg.name}/0"
    mkdir -p "$COMPATDATA"

    ${lib.optionalString (cfg.runtime == "proton") ''
      export STEAM_COMPAT_DATA_PATH="$COMPATDATA"
      export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPATDATA"
      export STEAM_COMPAT_APP_ID="0"

      export PROTON_RUN="${protonRun}"
    ''}

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") cfg.env
    )}

    cd "$GAMEDIR"
    ${cfg.preRun}
    ${
      if cfg.runScript != null then
        cfg.runScript
      else if cfg.runtime == "proton" then
        ''
          gamescope ${cfg.gamescopeArgs} -- \
            "$PROTON_RUN" "$GAMEDIR/${cfg.executable}"
        ''
      else if cfg.runtime == "native" then
        ''
          gamescope ${cfg.gamescopeArgs} -- \
            "$GAMEDIR/${cfg.executable}" "$@"
        ''
      else
        ''
          echo "No runScript or executable specified" >&2
          exit 1
        ''
    }
  '';

  # Runs outside bwrap: mounts overlay, then enters FHS
  wrapper =
    fhsEnv:
    pkgs.writeShellScript "${cfg.name}-wrapper" ''
      GAMEDIR="''${HOME:-.}/.strom/${cfg.name}"
      mkdir -p "$GAMEDIR"
      export STROM_OVERLAY=$(${prepareGameDir} "$GAMEDIR")

      cleanup() {
        fusermount -uz "$STROM_OVERLAY" 2>/dev/null
      }
      trap 'cleanup; kill -KILL -- -$$ 2>/dev/null' INT TERM
      trap cleanup EXIT

      # Run in new process group so kill -9 0 inside bwrap
      # doesn't kill this wrapper before cleanup runs
      setsid ${fhsEnv}/bin/${cfg.name}-fhs "$@" &
      FHS_PID=$!
      trap 'kill -KILL -- -$FHS_PID 2>/dev/null; cleanup; kill -KILL -- -$$ 2>/dev/null' INT TERM
      wait $FHS_PID 2>/dev/null
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

    executable = mkOption {
      type = types.str;
      default = "";
      description = "Game executable path relative to GAMEDIR (for proton/native runtime)";
    };

    gamescopeArgs = mkOption {
      type = types.str;
      default = "-W 1920 -H 1080 -w 1920 -h 1080";
      description = "Arguments for gamescope";
    };

    preRun = mkOption {
      type = types.str;
      default = "";
      description = "Shell commands to run before launching the game (inside FHS, has $GAMEDIR)";
    };

    runScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Custom run script. Overrides executable/gamescopeArgs if set.";
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
        let
          fhsEnv = pkgs.buildFHSEnv {
            name = "${cfg.name}-fhs";
            runScript = innerWrapper;
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
          };
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = cfg.name;
          version = "0";
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/bin
            ln -s ${wrapper fhsEnv} $out/bin/${cfg.name}
          '';
          inherit (cfg) meta;
        }
      else if cfg.runtime == "native" then
        pkgs.writeShellApplication {
          inherit (cfg) name meta;
          runtimeInputs = [ pkgs.gamescope ];
          text = ''
            USERDIR="''${HOME:-.}/.strom/${cfg.name}"
            mkdir -p "$USERDIR"
            GAMEDIR=$(${prepareGameDir} "$USERDIR")
            trap 'fusermount -uz "$GAMEDIR" 2>/dev/null' EXIT
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") cfg.env
            )}
            cd "$GAMEDIR"
            ${if cfg.runScript != null then cfg.runScript else "echo 'No runScript' >&2; exit 1"}
          '';
        }
      else
        # custom: FHS env with overlay mounted outside
        let
          customFhs = pkgs.buildFHSEnv {
            name = "${cfg.name}-fhs";
            runScript = innerWrapper;
            targetPkgs = cfg.targetPkgs;
            extraBwrapArgs = cfg.extraBwrapArgs;
          };
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = cfg.name;
          version = "0";
          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/bin
            ln -s ${wrapper customFhs} $out/bin/${cfg.name}
          '';
          inherit (cfg) meta;
        };
  };
}
