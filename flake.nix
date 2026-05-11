{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    wrappers.url = "github:lassulus/wrappers";
    wrappers.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      wrappers,
      git-hooks,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Single source of truth for the hook configuration; consumed by both
      # `checks.pre-commit-check` (for `nix flake check`) and the dev shell
      # (so `nix develop` installs the hooks into .git/hooks).
      mkPreCommit =
        system:
        git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt-rfc-style.enable = true;
            shellcheck.enable = true;
            ruff-format.enable = true;

            readme-up-to-date = {
              enable = true;
              name = "README is up to date";
              description = "Re-runs scripts/generate-readme.py and fails if README.md changed.";
              entry = "scripts/check-readme-generated.sh";
              language = "system";
              pass_filenames = false;
            };

            no-signed-commits = {
              enable = true;
              name = "no signed commits on push";
              description = "Refuse to push commits that carry a digital signature.";
              entry = "scripts/check-no-signed-commits.sh";
              language = "system";
              pass_filenames = false;
              stages = [ "pre-push" ];
            };
          };
        };
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      checks = forAllSystems (system: {
        pre-commit-check = mkPreCommit system;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          preCommit = mkPreCommit system;
        in
        {
          default = pkgs.mkShellNoCC {
            packages =
              (with pkgs; [
                nixfmt-tree
                nix-prefetch
                radicle-node
              ])
              ++ preCommit.enabledPackages;
            shellHook = ''
              ${preCommit.shellHook}
              echo '[*] to start distributed git, run `rad node start`'
            '';
          };
        }
      );

      nixosModules = {
        ipfs-mirror = import ./nixos/mirror-module.nix;
        default = self.nixosModules.ipfs-mirror;
      };

      lib = {
        mkGame =
          { lib, pkgs }:
          import ./lib/mk-game.nix {
            inherit lib pkgs wrappers;
            fetchIpfs = self.lib.fetchIpfs { inherit pkgs; };
          };
        gamescope = wrappers.lib.wrapModule (import ./lib/gamescope.nix);
        proton = wrappers.lib.wrapModule (import ./lib/proton.nix);
        fuse-overlayfs = wrappers.lib.wrapModule (import ./lib/fuse-overlayfs.nix);
        fetchIpfs =
          { pkgs }:
          import ./lib/fetch-ipfs.nix {
            inherit (pkgs)
              lib
              stdenvNoCC
              go-car
              curl
              cacert
              ;
            lassie = pkgs.callPackage ./pkgs/lassie.nix { };
          };
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

      packages = {
        aarch64-darwin.publish-ipns = import ./scripts/publish-ipns.nix {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          games = self.packages.x86_64-linux;
        };
        aarch64-darwin.lassie = nixpkgs.legacyPackages.aarch64-darwin.callPackage ./pkgs/lassie.nix { };
        x86_64-darwin.publish-ipns = import ./scripts/publish-ipns.nix {
          pkgs = nixpkgs.legacyPackages.x86_64-darwin;
          games = self.packages.x86_64-linux;
        };
      }
      // forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lassie = pkgs.callPackage ./pkgs/lassie.nix { };
          fetchIpfs = self.lib.fetchIpfs { inherit pkgs; };
          callPackage = pkgs.lib.callPackageWith (pkgs // { inherit self fetchIpfs; });
        in
        let
          games = builtins.mapAttrs (name: _: callPackage ./games/${name} { }) (builtins.readDir ./games);
        in
        games
        // {
          pin-ipfs = import ./scripts/pin-ipfs.nix { inherit pkgs games; };
          inherit lassie;
          publish-ipns = import ./scripts/publish-ipns.nix { inherit pkgs games; };
        }
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
