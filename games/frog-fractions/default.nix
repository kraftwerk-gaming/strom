{
  lib,
  pkgs,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };
in
mkGame {
  name = "frog-fractions";
  runtime = "native";

  src = pkgs.fetchurl {
    url = "https://archive.org/download/frog-fractions/FrogFractions.swf";
    hash = "sha256-HYVbtOttB7PfEXhPbWXDFlE4q8I5ZSwNRo5aZDH55t0=";
    name = "FrogFractions.swf";
  };

  buildScript = ''
    mkdir -p $out
    cp $src $out/FrogFractions.swf
  '';

  runScript = ''
    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -- \
      ${pkgs.ruffle}/bin/ruffle --no-gui "$GAMEDIR/FrogFractions.swf"
  '';
}
