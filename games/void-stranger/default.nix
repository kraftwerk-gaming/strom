{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "void-stranger";

  src = fetchIpfs {
    cid = "QmSAKT7sGXCbtv8S8AAKsTcSovsAkiKStmd6hso1eh6evB";
    fallbackUrl = "";
    hash = "sha256-4b8gk21kSf9rfurh9kHCnY4UMl6It6iryaQdXTLyU+I=";
    name = "void-stranger.zip";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y $src -o"$out"
  '';

  runtime = "proton";
  executable = "VoidStranger.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Void Stranger (via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "void-stranger";
  };
}
