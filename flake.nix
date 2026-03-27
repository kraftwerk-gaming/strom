{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          jazz2 = pkgs.callPackage ./games/jazz2 { };
          lemmings = pkgs.callPackage ./games/lemmings { };
          settlers2 = pkgs.callPackage ./games/settlers2 { };
          thief-gold = pkgs.callPackage ./games/thief-gold { };
        }
      );
    };
}
