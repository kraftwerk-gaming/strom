{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Clonk 4.07 (US) freeware release. Self-contained portable build:
  # unzip and run Clonk4.exe. Freeware activation: Spielername
  # "Freeware Player", code 3212739588 (see Freeware.txt in the archive).
  src = fetchIpfs {
    cid = "QmWydrkqvdj6b8Zisoixxsoi5e9M5CUAMvwRus3bXxN2Jb";
    fallbackUrl = "https://archive.org/download/clonk-complete-collection/Clonk%204%20%28Clonk%20World%29%20%281998%29/clonk407us.zip";
    hash = "sha256-XvqV4e9zDtXIc9riJog4R73KO8tBgCRxbPDwhGOs9B0=";
    name = "clonk407us.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "clonk-4";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
  '';

  runtime = "proton";
  executable = "Clonk4.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    PROTON_USE_WINED3D = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Clonk 4 (1998 freeware release, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "clonk-4";
  };
}
