{
  lib,
  stdenv,
  writeShellScriptBin,
  writeText,
  python3,
  nix,
  gameMeta,
}:

# A fullscreen pygame grid for picking games with a gamepad. The set of games is
# fixed at build time (gameMeta: slug + runtime + description) so the launcher
# matches the flake revision it was built from. Display metadata (name, genres,
# tags, ...) is read at runtime from each game's games/<slug>/steam.json +
# metadata.json -- the same per-game files the web GUI reads, so there is no
# catalog.json. Launching shells out to `nix run` against the public flake ref
# so the launcher itself stays tiny.

let
  manifest = writeText "strom-manifest.json" (builtins.toJSON gameMeta);
  py = python3.withPackages (ps: [ ps.pygame ]);
in
writeShellScriptBin "strom-launcher" ''
  export PATH=${lib.makeBinPath [ nix ]}:$PATH
  export STROM_MANIFEST=${manifest}
  export STROM_GAMES=${../../games}
  export STROM_SYSTEM=${stdenv.hostPlatform.system}
  : "''${STROM_FLAKE:=github:kraftwerk-gaming/strom}"
  export STROM_FLAKE
  exec ${py.interpreter} ${./launcher.py} "$@"
''
