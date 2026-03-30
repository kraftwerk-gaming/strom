{
  callPackage,
  lib,
  pkgs,
  fetchurl,
  p7zip,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };
in
mkGame {
  name = "untitled-goose-game";

  src = fetchurl {
    url = "https://archive.org/download/untitled-goose-game-portable-hoang-long/Untitled_Goose_Game_Portable%5BHoangLong%5D.7z";
    hash = "sha256-CAcpFF28cM/Gu032tHL9SdBHHAXCWx2w6ycqL8HEG+Y=";
    name = "goose.7z";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x $src -o/tmp/goose
    mv /tmp/goose/DATA/* "$out"/
  '';

  runtime = "proton";
  executable = "Untitled.exe";
  gamescopeArgs = "-W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland";

  meta = {
    description = "Untitled Goose Game (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "untitled-goose-game";
  };
}
