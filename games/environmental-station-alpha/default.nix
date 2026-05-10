{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  src = fetchIpfs {
    cid = "QmSKfKZbygBUXXknED9vQUpaY4yjApjHMqTXq4cwtDD9xQ";
    fallbackUrl = "https://archive.org/download/environmental-sa-v-02.06.2020/Environmental%20SA%20%5Bv02.06.2020%5D.rar";
    hash = "sha256-TJa8urBX+ha2gITpXI2OzPVSlidT+0kcxhk6P7mgjpA=";
    name = "environmental-station-alpha-2020-06-02.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "environmental-station-alpha";

  ipfsSources = [ src ];

  inherit src;

  nativeBuildInputs = [ unar ];

  # Archive contains: Environmental Station Alpha [v02.06.2020]/
  #   Environmental SA [20-06-20]/  ← actual game (GameMaker Studio,
  #     Environmental Station Alpha.exe + Data/)
  #   _Redist/  (vcredist installers — skip, Proton handles deps)
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR" "$src"
    cp -r "$TMPDIR/Environmental Station Alpha [v02.06.2020]/Environmental SA [20-06-20]"/. "$out"/
  '';

  runtime = "proton";
  executable = "Environmental Station Alpha.exe";

  saveLocations = [ "AppData/Roaming/MMFApplications" ];

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
    description = "Environmental Station Alpha (Hempuli, 2015, GameMaker Studio, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "environmental-station-alpha";
  };
}
