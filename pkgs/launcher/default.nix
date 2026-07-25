{
  lib,
  writeShellScriptBin,
  writeText,
  runCommand,
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

  # Merged display catalog, assembled at build time from each game's
  # games/<slug>/steam.json (Steam-fetched) + metadata.json (hand-maintained)
  # by scripts/assemble-catalog.py -- the same aggregate the web GUI builds.
  # Read at startup to label tiles and render the selected-game subtitle. A
  # game with neither file just falls back to its nix description label.
  catalog = runCommand "strom-catalog.json" { nativeBuildInputs = [ python3 ]; } ''
    python3 ${../../scripts/assemble-catalog.py} ${../../games} > "$out"
  '';

  py = python3.withPackages (ps: [ ps.pygame ]);
in
writeShellScriptBin "strom-launcher" ''
  export PATH=${lib.makeBinPath [ nix ]}:$PATH
  export STROM_MANIFEST=${manifest}
  export STROM_CATALOG=${catalog}
  : "''${STROM_FLAKE:=github:kraftwerk-gaming/strom}"
  export STROM_FLAKE
  exec ${py.interpreter} ${./launcher.py} "$@"
''
