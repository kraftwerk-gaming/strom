{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unshield,
}:

let
  gameISO = fetchIpfs {
    cid = "QmWenFrRUnLTrxuDBcYGt3PqaAEhW7T5fK5MZUF1knVPJY";
    fallbackUrl = "https://archive.org/download/bfii_20220801/BFII.ISO";
    hash = "sha256-p9gvAovXm1SrYmNoyXhCLpwPZ7ya8RkSxC+qR6LQb98=";
    name = "BFII.ISO";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "star-wars-battlefront-2";

  src = gameISO;

  nativeBuildInputs = [
    p7zip
    unshield
  ];

  buildScript = ''
    mkdir -p /tmp/iso
    7z x ${gameISO} -o/tmp/iso

    mkdir -p "$out"

    # Extract game data from InstallShield CABs
    unshield -g Files -d /tmp/game x /tmp/iso/GameData/data1.hdr
    cp -r /tmp/game/Files/* "$out/"

    # Extract launcher
    unshield -g Launcher_Files_Exe -d /tmp/launcher x /tmp/iso/GameData/data1.hdr
    cp /tmp/launcher/Launcher_Files_Exe/LaunchBFII.exe "$out/"

    # Copy the main executable from ISO (not in InstallShield CABs)
    cp /tmp/iso/GameData/GameData/battlefrontII.exe "$out/"

    rm -rf /tmp/iso /tmp/game /tmp/launcher
  '';

  runtime = "proton";
  executable = "battlefrontII.exe";

  copyGlobs = [
    "SaveGames/"
  ];

  env = {
    PULSE_LATENCY_MSEC = "60";
  };

  meta = {
    description = "Star Wars: Battlefront II (2005) v1.1 Rerelease via Proton and gamescope";
    platforms = [ "x86_64-linux" ];
    mainProgram = "star-wars-battlefront-2";
  };
}
