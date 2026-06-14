{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Deep Rock Galactic: Survivor (Funday Games / Ghost Ship Publishing,
  # 2024 Early Access). Unity IL2CPP build (globalgamemanagers +
  # il2cpp_data + GameAssembly.dll), NOT Unreal despite the franchise.
  # archive.org "cracked game" zip ships the clean Steam build with a
  # Goldberg/gbe_fork steam_api64.dll already swapped in and a populated
  # steam_settings/ (appid 2321470, achievements.json, DLC.txt) next to
  # it, so no Steam client is needed offline — same shape as ULTRAKILL.
  src = fetchIpfs {
    cid = "QmSL5h9UesxVdWGxAdPzXEgr1cTJ2puw2LJv71mcUgtSR4";
    fallbackUrl = "https://archive.org/download/deep-rock-galactic-survivor/DeepRockGalacticSurvivor.zip";
    hash = "sha256-/tbf0nE/6lFHxmShVuNFsmJ+/eFT4yxSp7/djyoThTQ=";
    name = "deep-rock-galactic-survivor.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "deep-rock-galactic-survivor";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # Zip root is the flat game tree: "DRG Survivor.exe" + UnityPlayer.dll +
  # GameAssembly.dll + "DRG Survivor_Data/" with the bundled Goldberg emu.
  # Drop the _Redist/ pre-installer tree (VC/DirectX/dotnet/OpenAL) — those
  # are unnecessary under Proton.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
    rm -rf "$out/_Redist"
  '';

  runtime = "proton";
  executable = "DRG Survivor.exe";

  env = {
    SteamAppId = "2321470";
    SteamGameId = "2321470";
  };

  # Unity writes saves/settings/Player.log under AppData/LocalLow per the
  # company/product from DRG Survivor_Data/app.info (Funday Games / DRG
  # Survivor); pull them out of the wineprefix so they survive proton bumps.
  saveLocations = [ "AppData/LocalLow/Funday Games/DRG Survivor" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Deep Rock Galactic: Survivor (Funday Games 2024, Unity auto-shooter via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "deep-rock-galactic-survivor";
  };
}
