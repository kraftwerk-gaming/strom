{
  self,
  lib,
  pkgs,
  fetchIpfs,
  scummvm,
  gamescope,
  unzip,
  bchunk,
  p7zip,
}:

let
  # Day of the Tentacle (1993 LucasArts) CD-ROM redump (USA, Europe).
  # The talkie CD release: English voice acting, music is digital iMUSE
  # synth (no Red Book audio — the cue declares a single MODE1/2352
  # data track), so ScummVM only needs the data files extracted.
  src = fetchIpfs {
    cid = "Qmb4tE5gCLyppBRWu94wnNpjcbdMt9Dqt1W9EMev8HaW7Z";
    fallbackUrl = "https://archive.org/download/20230618_20230618_0815/Maniac%20Mansion%20-%20Day%20of%20the%20Tentacle%20%28USA%2C%20Europe%29.zip";
    hash = "sha256-DfW8WG0M8OgeNnDS3llnidOej3o+qNt6vfOXaHDcvpo=";
    name = "day-of-the-tentacle.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "day-of-the-tentacle";

  inherit src;

  nativeBuildInputs = [
    unzip
    bchunk
    p7zip
  ];

  # The zip ships a CD redump (.bin + .cue). bchunk converts it to
  # out01.iso (the data track), then 7z pulls the DOTT/ tree out so
  # ScummVM can auto-detect the game.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cd "$TMPDIR/zip"
    bchunk *.bin *.cue track
    7z x -y track01.iso DOTT
    cp -r DOTT/. "$out"/
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
    description = "Day of the Tentacle (1993 LucasArts CD talkie edition, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "day-of-the-tentacle";
  };
}
