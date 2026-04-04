{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "untitled-goose-game";

  src = fetchIpfs {
    cid = "QmQQ7zeZckvfqvNn79NRVLqU2SKgqKWioRM3yiLqexki9c";
    fallbackUrl = "https://archive.org/download/untitled-goose-game-portable-hoang-long/Untitled_Goose_Game_Portable%5BHoangLong%5D.7z";
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
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Untitled Goose Game (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "untitled-goose-game";
  };
}
