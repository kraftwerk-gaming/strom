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
        mkGame = { lib, pkgs }: import ./lib/mk-game.nix { inherit lib pkgs wrappers; };
        gamescope = import ./lib/gamescope.nix { wlib = wrappers.lib; };
        proton = import ./lib/proton.nix { wlib = wrappers.lib; };
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
          fetchIpfs = import ./lib/fetch-ipfs.nix {
            inherit (pkgs) lib stdenvNoCC ipget curl cacert;
          };
          callPackage = pkgs.lib.callPackageWith (pkgs // { inherit self fetchIpfs; });
        in
        builtins.mapAttrs (name: _: callPackage ./games/${name} { }) (builtins.readDir ./games)
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          games = self.packages.${system};
          gameMeta = builtins.mapAttrs (_: p: {
            description = p.meta.description or null;
            runtime = p.passthru.runtime or "unknown";
          }) games;
          launcher = pkgs.callPackage ./pkgs/launcher { inherit gameMeta; };
        in
        {
          launcher = {
            type = "app";
            program = "${launcher}/bin/strom-launcher";
          };
        }
      );
    };
}
