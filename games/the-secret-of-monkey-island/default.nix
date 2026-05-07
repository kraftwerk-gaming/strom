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
  # SE Talkie Edition for ScummVM: original SCUMM data files (monkey.000,
  # monkey.001) plus the SE remake's English voice-over (monkey.sof) and
  # FLAC rips of the original CD audio music tracks (track1..N.flac).
  # ScummVM auto-detects the directory and plays everything: original
  # game/visuals + speech + music. The fan project is required because
  # the 1992 EU CD ISO this archive otherwise ships only contains the
  # data tracks; CD-Audio music is on Red Book tracks not visible in
  # the ISO filesystem.
  src = fetchIpfs {
    cid = "QmWQubvmz8QmRtk6beb4bNzKmwvv9vwzGMYcHXejB1yvrG";
    fallbackUrl = "https://archive.org/download/monkeyislandtalkiescummvm/The%20Secret%20of%20Monkey%20Island%20%28SE%20Talkie%29.zip";
    hash = "sha256-Wqkapeeh6Wp1LdZHOa0sUZ2+JFf2zhsRzBvyB+6TFmY=";
    name = "the-secret-of-monkey-island-se-talkie.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-secret-of-monkey-island";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/The Secret of Monkey Island (SE Talkie)"/. "$out"/
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
    description = "The Secret of Monkey Island (1990 Lucasfilm, SE Talkie fan-edition for ScummVM: original VGA + SE speech + CD music)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-secret-of-monkey-island";
  };
}
