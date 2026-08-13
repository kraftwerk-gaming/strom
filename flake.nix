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

            metadata-synced = {
              enable = true;
              name = "metadata build keys synced";
              description = "Re-runs scripts/sync-metadata.py and fails if any games/<slug>/metadata.json build keys are stale.";
              entry = "scripts/check-metadata-synced.sh";
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
            # Player-facing bool/enum knobs, if the recipe declared any
            # (lib/mk-game.nix `userSettings`); drives the launcher's
            # customize view.
            settings = p.passthru.settingsSchema or [ ];
          }) games;

          # The Android SDK is unfree and its licence must be accepted
          # explicitly, so the APK build gets its own nixpkgs instance
          # rather than tainting the one every game is built from.
          pkgsAndroid = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              android_sdk.accept_license = true;
            };
          };
        in
        {
          patched-pkgs = {
            proton = pkgs.callPackage ./pkgs/proton.nix { };
            sdl2 = pkgs.callPackage ./pkgs/sdl2.nix { };
          };
          inherit games;
          # revCount is monotonic across the repo's history, which is
          # exactly what versionCode has to be, and it needs no manual
          # bump before a release. A dirty or shallow checkout has no
          # revCount, so local builds fall back to 1 -- CI must clone with
          # full history or every release would claim the same version.
          #
          # The leading number is the release this is built towards, and it
          # does need bumping when a tag is cut. Obtainium reconciles the
          # release it sees with the versionName of the APK installed, and
          # a v0.1.1 release carrying "0.1.0+..." leaves it unable to, so
          # it falls back to a pseudo-version and says so on the app's
          # page. Everything after the + is build metadata that names the
          # exact commit, which is more useful than the release number for
          # anything except matching a release.
          androidApp = pkgsAndroid.callPackage ./pkgs/android-app {
            versionCode = self.revCount or 1;
            versionName = "0.1.2+r${toString (self.revCount or 0)}.${self.shortRev or "dirty"}";
          };
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

      # Android outputs. Thin aliases onto each game's `android`
      # submodule (see lib/android/default.nix) so the useful paths are
      # `nix build .#androidManifests.<slug>` rather than
      # `.#modules.x86_64-linux.<slug>.android.outputs.manifest`. Lazy
      # per attribute: a game that doesn't define an APK only errors
      # when its `apks` attribute is actually evaluated.
      #
      # androidManifests  per-game descriptor for the Strom Android
      #                   client (backend, payload CID, launch args).
      # androidPayloads   the zip an operator builds and IPFS-pins to
      #                   make a game available on Android.
      # apks              per-game self-contained APK, where one exists.
      # androidApp        the client itself: one APK for every game, which
      #                   reads the manifests above and fetches payloads by
      #                   CID. `nix build .#androidApp`.
      apks = nixpkgs.lib.mapAttrs (_: m: m.android.outputs.apk) self.modules.x86_64-linux;
      androidManifests = nixpkgs.lib.mapAttrs (
        _: m: m.android.outputs.manifest
      ) self.modules.x86_64-linux;
      androidPayloads = nixpkgs.lib.mapAttrs (_: m: m.android.outputs.payload) self.modules.x86_64-linux;
      androidApp = self.legacyPackages.x86_64-linux.androidApp;
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
