{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "animal-well";

  # The game tree, pinned as one reproducible tar.zst bundle: the desktop
  # extracts it into the overlay base and the Android client into its
  # game directory, from the same CID. (Originally the AnkerGames RAR5
  # release, minus its two advert files.)
  src = fetchIpfs {
    cid = "bafybeihxbuklzovvuldc2a5rxthzqld5lvbncpgcddmx5enxfcs4kckyjy";
    bundle = true;
    hash = "sha256-i6GQWZ0ffoTFnPTv6ewYguWV58CUuQRPGd7lnYQWifk=";
    name = "animal-well";
    size = 31170161;
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
