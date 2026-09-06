{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "animal-well";

  # The game tree itself, pinned as a directory: the desktop overlays it
  # and the Android client unpacks it, from the same CID, with nothing to
  # extract on either side. (Originally the AnkerGames RAR5 release,
  # minus its two advert files.)
  src = fetchIpfs {
    cid = "bafybeifrlj54674zds5tazgywt76xjvuywfc2pkbz6pvaoaj5gmzmatzhu";
    directory = true;
    hash = "sha256-i6GQWZ0ffoTFnPTv6ewYguWV58CUuQRPGd7lnYQWifk=";
    name = "animal-well";
    size = 36837264;
  };

  runtime = "proton";
  saveLocations = [ "AppData/LocalLow/Billy Basso/Animal Well" ];
  executable = "Animal Well.exe";

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

  # The game is D3D12-only. Under DXVK, the manifest default, it stops at
  # "Failed to create D3D12 Device (error = 0x80004002)" before its first
  # frame (measured, AYN Thor); VKD3D runs it.
  android.containerConfig.dxwrapper = "vkd3d";

  meta = {
    description = "ANIMAL WELL (Billy Basso 2024, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "animal-well";
  };
}
