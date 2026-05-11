# fhsUserEnv wrapperModule (raw module source).
#
# Wraps a target binary inside a synthetic FHS rootfs built by
# pkgs.buildFHSEnv. config.runScript runs inside the chroot where
# /usr/lib, /usr/lib32, /usr/bin etc. resolve to targetPkgs. The option
# name matches buildFHSEnv's `runScript` parameter.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  fhsEnv = config.pkgs.buildFHSEnv {
    name = config.binName;
    targetPkgs = config.targetPkgs;
    extraBwrapArgs = config.extraBwrapArgs;
    runScript = config.pkgs.writeShellScript "${config.binName}-runscript" ''
      ${config.preHook}
      ${lib.optionalString (config.postHook == "") "exec"} "${config.runScript}" "$@"
      ${config.postHook}
    '';
  };
in
{
  _class = "wrapper";

  options = {
    targetPkgs = mkOption {
      type = types.functionTo (types.listOf types.package);
      default = _: [ ];
      description = "Function from pkgs to packages in the FHS rootfs.";
    };

    extraBwrapArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra bwrap args passed to buildFHSEnv's internal bwrap.";
    };

    runScript = mkOption {
      type = types.either types.path types.str;
      description = "Path to the script/binary to exec inside the FHS chroot.";
    };
  };

  config = {
    binName = lib.mkDefault "fhs-wrapper";
    package = fhsEnv;
    outputs.wrapper = fhsEnv;
  };
}
