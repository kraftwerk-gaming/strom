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
  # Curated per-game metadata for the grid (display name, genres, year,
  # developers). This is the same aggregate the web GUI reads: Steam/Lutris
  # data with each game's games/<slug>/gui.json merged over it. Read at
  # startup to label tiles and render the selected-game subtitle. Optional:
  # a checkout without the generated catalog still builds and just falls
  # back to the nix description labels.
  catalog = ../../web/catalog.json;
  hasCatalog = builtins.pathExists catalog;

  py = python3.withPackages (ps: [ ps.pygame ]);
in
writeShellScriptBin "strom-launcher" ''
  export PATH=${lib.makeBinPath [ nix ]}:$PATH
  export STROM_MANIFEST=${manifest}
  ${lib.optionalString hasCatalog "export STROM_CATALOG=${catalog}"}
  : "''${STROM_FLAKE:=github:kraftwerk-gaming/strom}"
  export STROM_FLAKE
  exec ${py.interpreter} ${./launcher.py} "$@"
''
