{
  fetchurl,
  jazz2,
  lib,
  pkgs,
  unzip,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };

  jazz2-mp = jazz2.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [
      (lib.cmakeBool "WITH_MULTIPLAYER" true)
    ];
  });
in
mkGame {
  name = "jazz2";

  src = fetchurl {
    url = "https://archive.org/download/jazz-jackrabbit-2-1.24-the-secret-files-plus/Jazz%20Jackrabbit%202%201.24%20The%20Secret%20Files%20Plus.zip";
    hash = "sha256-ceeXiGUy5QDq1HQPo5gpyQe2odAK1F5frofBXegeXi8=";
    name = "jazz-jackrabbit-2-tsf.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -j -o $src -d "$out/"
  '';

  runtime = "native";

  runScript = ''
    # jazz2 looks for data at XDG_DATA_HOME/Jazz² Resurrection/Source/
    export XDG_DATA_HOME="$GAMEDIR/.xdg-data"
    datadir="$XDG_DATA_HOME/Jazz² Resurrection"
    mkdir -p "$XDG_DATA_HOME"
    ln -sfn "$GAMEDIR" "$datadir/Source" 2>/dev/null || {
      mkdir -p "$datadir"
      ln -sfn "$GAMEDIR" "$datadir/Source"
    }

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 --expose-wayland -- \
      ${lib.getExe jazz2-mp}
  '';

  meta = jazz2.meta // {
    description = "Jazz Jackrabbit 2 (Jazz² Resurrection with game data and multiplayer)";
    mainProgram = "jazz2";
  };
}
