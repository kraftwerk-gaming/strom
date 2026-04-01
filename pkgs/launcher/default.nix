{
  lib,
  writeShellScriptBin,
  writeText,
  python3,
  nix,
  gameMeta,
}:

# A fullscreen pygame grid for picking games with a gamepad. The set of
# games is fixed at build time so the launcher always matches the flake
# revision it was built from. Launching shells out to `nix run` against
# the public flake ref so the launcher itself stays tiny and does not
# pull every game into its closure.

let
  manifest = writeText "strom-manifest.json" (builtins.toJSON gameMeta);

  py = python3.withPackages (ps: [ ps.pygame ]);
in
writeShellScriptBin "strom-launcher" ''
  export PATH=${lib.makeBinPath [ nix ]}:$PATH
  export STROM_MANIFEST=${manifest}
  : "''${STROM_FLAKE:=github:kraftwerk-gaming/strom}"
  export STROM_FLAKE
  exec ${py.interpreter} ${./launcher.py} "$@"
''
