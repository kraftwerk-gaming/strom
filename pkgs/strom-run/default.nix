{
  lib,
  rustPlatform,
}:

# Atomic cgroup-v2 teardown supervisor for strom game process trees;
# replaces the host-side bash lifecycle logic in lib/bwrap.nix. Kept
# pkgs-agnostic (rustix-free, libc-only, no C deps) so a future Android
# pivot can callPackage it under pkgsCross.*.pkgsStatic unchanged.
rustPlatform.buildRustPackage {
  pname = "strom-run";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Atomic cgroup teardown supervisor for strom game process trees";
    mainProgram = "strom-run";
    platforms = lib.platforms.linux;
  };
}
