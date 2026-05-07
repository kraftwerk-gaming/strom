{
  self,
  lib,
  pkgs,
  fetchIpfs,
  scummvm,
  gamescope,
  unzip,
}:

let
  # SE Talkie Edition for ScummVM: original SCUMM data files (monkey2.000,
  # monkey2.001) plus the SE remake's English voice-over (monkey2.sof).
  # ScummVM auto-detects the directory and plays the original game/visuals
  # with SE speech. The fan project is required because the 1991 floppy/CD
  # release shipped without speech and the SE's voice-over was never
  # released as a standalone speech pack.
  src = fetchIpfs {
    cid = "QmYs37wpRTvw1ihxgzd4HR8Zf1Y1QqSATd8rHZMKETTuTm";
    fallbackUrl = "https://archive.org/download/monkeyislandtalkiescummvm/Monkey%20Island%202%20-%20LeChuck%27s%20Revenge%20%28SE%20Talkie%29.zip";
    hash = "sha256-rjFqRqA6Ms502wiLivuAAH8LOXuvb66P0SK6zw/tB7k=";
    name = "monkey-island-2-se-talkie.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "monkey-island-2-special-edition";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/Monkey Island 2 - LeChuck's Revenge (SE Talkie)"/. "$out"/
  '';

  runtime = "native";

  runScript = ''
    mkdir -p "$STROM_GAMEDIR/save"
    exec ${gamescope}/bin/gamescope -W 1920 -H 1080 -r 60 --expose-wayland -- \
      ${scummvm}/bin/scummvm \
      --fullscreen \
      --path="$GAMEDIR" \
      --savepath="$STROM_GAMEDIR/save" \
      --auto-detect
  '';

  meta = {
    description = "Monkey Island 2: LeChuck's Revenge (1991 LucasArts, SE Talkie fan-edition for ScummVM: original VGA + SE speech)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "monkey-island-2-special-edition";
  };
}
