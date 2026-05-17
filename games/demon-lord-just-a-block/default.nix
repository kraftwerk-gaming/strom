{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "demon-lord-just-a-block";

  src = fetchIpfs {
    cid = "QmUGu12nm8YfouvUUbsj8iXj9PBpcLTpBE3DAqtQtLxEx4";
    fallbackUrl = "https://ipfs.io/ipfs/QmUGu12nm8YfouvUUbsj8iXj9PBpcLTpBE3DAqtQtLxEx4";
    hash = "sha256-2pPWTZzsOCfLHBTF5bU8RpKdpf3XyjDHYCVOr75akhY=";
    name = "demon-lord-just-a-block-ankergames-v2605063.zip";
  };

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
    mv "$out/DemonLordJustABlock/"* "$out/"
    rmdir "$out/DemonLordJustABlock"
  '';

  runtime = "proton";

  saveLocations = [ "AppData/LocalLow/YuWave/DemonLordJustABlock" ];
  executable = "DemonLordJustABlock.exe";

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

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Demon Lord Just A Block (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "demon-lord-just-a-block";
  };
}
