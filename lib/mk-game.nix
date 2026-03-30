{ lib, pkgs }:

config:

let
  mod = lib.evalModules {
    modules = [
      ./mk-game-options.nix
      { _module.args = { inherit pkgs; }; }
      config
    ];
  };
in
mod.config._build
