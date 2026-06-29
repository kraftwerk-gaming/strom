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
        # Compile + (future) unit-test strom-run in isolation, so it can be
        # built via `nix build .#checks.<system>.strom-run` without running
        # the whole-flake `nix flake check`.
        strom-run = self.legacyPackages.${system}.scripts.strom-run;
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
        strom-desktop = import ./nixos/desktop-module.nix { inherit self; };
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
        fetchIpfs =
          { pkgs }:
          import ./lib/fetch-ipfs.nix {
            inherit (pkgs)
              lib
              stdenvNoCC
              aria2
              curl
              cacert
              ;
          };
      };

      legacyPackages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          games = builtins.mapAttrs (_: m: m.outputs.wrapper) self.modules.${system};
          gameMeta = builtins.mapAttrs (_: p: {
            description = p.meta.description or null;
            runtime = p.passthru.runtime or "unknown";
          }) games;
        in
        {
          patched-pkgs = {
            proton = pkgs.callPackage ./pkgs/proton.nix { };
            sdl2 = pkgs.callPackage ./pkgs/sdl2.nix { };
          };
          inherit games;
          scripts = {
            launcher = pkgs.callPackage ./pkgs/launcher { inherit gameMeta; };
            gui = pkgs.callPackage ./pkgs/gui { };
            strom-launch = pkgs.callPackage ./pkgs/strom-launch { inherit gameMeta; };
            pin-ipfs = import ./scripts/pin-ipfs.nix { inherit pkgs games; };
            publish-ipns = import ./scripts/publish-ipns.nix { inherit pkgs games; };
            screenshot = pkgs.callPackage ./pkgs/screenshot.nix { };
            strom-ip = pkgs.callPackage ./pkgs/strom-ip.nix { };
            strom-run = pkgs.callPackage ./pkgs/strom-run { };
          };
        }
      );

      modules = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          fetchIpfs = self.lib.fetchIpfs { inherit pkgs; };
          callPackage = pkgs.lib.callPackageWith (pkgs // { inherit self fetchIpfs; });
        in
        builtins.mapAttrs (name: _: callPackage ./games/${name} { }) (builtins.readDir ./games)
      );

      packages = forAllSystems (system: self.legacyPackages.${system}.games);

      # Android APK outputs. Thin alias: a game's `android` submodule
      # exposes an `outputs.apk` derivation (per-game seam, see
      # lib/android/default.nix); this remaps the path so
      # `nix build .#apks.<slug>` works without typing out
      # `.#modules.x86_64-linux.<slug>.android.outputs.apk`. Lazy per
      # attribute: games without an APK definition only error when
      # their attribute is actually evaluated.
      apks = nixpkgs.lib.mapAttrs (_: m: m.android.outputs.apk) self.modules.x86_64-linux;
      apps = forAllSystems (
        system:
        let
          scripts = self.legacyPackages.${system}.scripts;
        in
        {
          gui = {
            type = "app";
            program = "${scripts.gui}/bin/strom-gui";
          };
          launcher = {
            type = "app";
            program = "${scripts.launcher}/bin/strom-launcher";
          };
          strom-launch = {
            type = "app";
            program = "${scripts.strom-launch}/bin/strom-launch";
          };
        }
      );
    };
}
