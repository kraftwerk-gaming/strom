{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    wrappers.url = "github:lassulus/wrappers";
    wrappers.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, wrappers, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      lib = {
        mkGame = { lib, pkgs }: import ./lib/mk-game.nix { inherit lib pkgs; };
        retroarch = import ./lib/retroarch.nix { wlib = wrappers.lib; };
      };

      legacyPackages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          patched-pkgs = {
            fuse-overlayfs = pkgs.callPackage ./pkgs/fuse-overlayfs.nix { };
            proton = pkgs.callPackage ./pkgs/proton.nix { };
            sdl2 = pkgs.callPackage ./pkgs/sdl2.nix { };
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          callPackage = pkgs.lib.callPackageWith (pkgs // { inherit self; });
        in
        builtins.mapAttrs (name: _: callPackage ./games/${name} { }) (builtins.readDir ./games)
      );
    };
}
