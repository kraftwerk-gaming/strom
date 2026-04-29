{
  self,
  fetchIpfs,
  gamescope,
  jazz2,
  lib,
  pkgs,
  runCommandLocal,
  unzip,
}:

let

  jazz2-mp = jazz2.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [
      (lib.cmakeBool "WITH_MULTIPLAYER" true)
    ];
  });

  gameSrc = fetchIpfs {
    cid = "QmYfukSFCe24fSoJ6TVrFDG8153nfVVyh9FapcPpbrdfjb";
    fallbackUrl = "https://archive.org/download/jazz-jackrabbit-2-1.24-the-secret-files-plus/Jazz%20Jackrabbit%202%201.24%20The%20Secret%20Files%20Plus.zip";
    hash = "sha256-ceeXiGUy5QDq1HQPo5gpyQe2odAK1F5frofBXegeXi8=";
    name = "jazz-jackrabbit-2-tsf.zip";
  };

  sourceData =
    runCommandLocal "jazz-jackrabbit-2-source"
      {
        nativeBuildInputs = [ unzip ];
      }
      ''
        mkdir -p "$out"
        unzip -j -o ${gameSrc} -d "$out/"
      '';

  # Pre-generate the cache by running jazz-jackrabbit-2 --server (headless)
  gameData = runCommandLocal "jazz-jackrabbit-2-data" { } ''
    mkdir -p "$out/Jazz² Resurrection"
    ln -s ${sourceData} "$out/Jazz² Resurrection/Source"

    export HOME=$(mktemp -d)
    XDG_DATA_HOME="$out" ${lib.getExe jazz2-mp} --server 2>&1 || true

    # Verify cache was created
    test -f "$out/Jazz² Resurrection/Cache/Source.pak"
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "jazz-jackrabbit-2";

  ipfsSources = [ gameSrc ];
  src = gameData;
  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";

  runScript = ''
    # jazz-jackrabbit-2 uses XDG_DATA_HOME for game data and XDG_CONFIG_HOME for saves/config
    export XDG_DATA_HOME="$GAMEDIR"
    export XDG_CONFIG_HOME="$GAMEDIR"

    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -w 1920 -h 1080 --expose-wayland -- \
      ${lib.getExe jazz2-mp}
  '';

  meta = jazz2.meta // {
    description = "Jazz Jackrabbit 2 (Jazz² Resurrection with game data and multiplayer)";
    mainProgram = "jazz-jackrabbit-2";
  };
}
