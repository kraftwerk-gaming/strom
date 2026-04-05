{
  self,
  bchunk,
  fetchIpfs,
  fheroes2,
  lib,
  p7zip,
  pkgs,
  unzip,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "heroes-of-might-and-magic-2-gold";

  src = fetchIpfs {
    cid = "QmRaZGqtcgX9cHNJXhkyc2czyw1qxjSvkAWRPjfEYCyVRi";
    fallbackUrl = "https://archive.org/download/heroes-of-might-and-magic-2-gold.-7z/Heroes%20of%20Might%20and%20Magic%202%20Gold.7z";
    hash = "sha256-QMwZHzxBTGuzDYNtQzVOaymILWC0vhHXPyMyKGRN+78=";
    name = "heroes-of-might-and-magic-2-gold.7z";
  };

  nativeBuildInputs = [
    bchunk
    p7zip
    unzip
  ];

  buildScript =
    let
      cdBin = fetchIpfs {
        cid = "QmXSHLnrpjALQJiboU8NPjttvgmmaLgeZxYRTZuKcBajUX";
        fallbackUrl = "https://archive.org/download/heroes-2-gold/Heroes2_Gold.bin";
        hash = "sha256-2l1BbjxTZjuWXf9rUEjbnk9G06jciY8pFvHYXH0JgbM=";
        name = "heroes-of-might-and-magic-2-gold-cd.bin";
      };
      cdCue = fetchIpfs {
        cid = "bafkreid25ep3hzdfntrcvipy74vuatwdgva74nootqbmtsjypjzhdqgupa";
        fallbackUrl = "https://archive.org/download/heroes-2-gold/Heroes2_Gold.cue";
        hash = "sha256-eukfs+RlbOIqofj/K0BOwzVB/jXOnALJyTh6cnHA1Hg=";
        name = "heroes-of-might-and-magic-2-gold-cd.cue";
      };
    in
    ''
      mkdir -p "$out"

      # Extract game data from portable install
      7z x $src -o/tmp/heroes2
      cp -r "/tmp/heroes2/Heroes of Might and Magic 2 Gold/_dosbox/_gamefiles"/* "$out/"

      # Extract campaign videos from CD
      mkdir -p /tmp/heroes2-cd
      cd /tmp/heroes2-cd
      bchunk ${cdBin} ${cdCue} track
      7z x track01.iso -o/tmp/heroes2-iso
      cp -r /tmp/heroes2-iso/Heroes2/ANIM "$out/"
    '';

  runtime = "native";

  runScript = ''
    # fheroes2 looks for data at XDG_DATA_HOME/fheroes2/
    # and config at XDG_CONFIG_HOME/fheroes2/
    export XDG_DATA_HOME="$GAMEDIR/.xdg-data"
    export XDG_CONFIG_HOME="$GAMEDIR/.xdg-config"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
    ln -sfn "$GAMEDIR" "$XDG_DATA_HOME/fheroes2"

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 --expose-wayland -- \
      ${lib.getExe fheroes2}
  '';

  meta = {
    description = "Heroes of Might & Magic II Gold (via fheroes2)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "heroes-of-might-and-magic-2-gold";
  };
}
