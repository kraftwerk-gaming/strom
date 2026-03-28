{
  bchunk,
  fetchurl,
  fheroes2,
  lib,
  p7zip,
  runCommandLocal,
  stdenvNoCC,
  unzip,
  writeShellScript,
}:

let
  gameArchive = fetchurl {
    url = "https://archive.org/download/heroes-of-might-and-magic-2-gold.-7z/Heroes%20of%20Might%20and%20Magic%202%20Gold.7z";
    hash = "sha256-QMwZHzxBTGuzDYNtQzVOaymILWC0vhHXPyMyKGRN+78=";
    name = "homm2-gold.7z";
  };

  # Original CD image (contains campaign videos in ANIM/)
  cdBin = fetchurl {
    url = "https://archive.org/download/heroes-2-gold/Heroes2_Gold.bin";
    hash = "sha256-2l1BbjxTZjuWXf9rUEjbnk9G06jciY8pFvHYXH0JgbM=";
    name = "homm2-cd.bin";
  };

  cdCue = fetchurl {
    url = "https://archive.org/download/heroes-2-gold/Heroes2_Gold.cue";
    hash = "sha256-eukfs+RlbOIqofj/K0BOwzVB/jXOnALJyTh6cnHA1Hg=";
    name = "homm2-cd.cue";
  };

  gameData =
    runCommandLocal "homm2-data"
      {
        nativeBuildInputs = [
          bchunk
          p7zip
          unzip
        ];
      }
      ''
        mkdir -p "$out"

        # Extract game data from portable install
        7z x ${gameArchive} -o/tmp/homm2
        cp -r "/tmp/homm2/Heroes of Might and Magic 2 Gold/_dosbox/_gamefiles"/* "$out/"

        # Extract campaign videos from CD
        mkdir -p /tmp/homm2-cd
        cd /tmp/homm2-cd
        bchunk ${cdBin} ${cdCue} track
        7z x track01.iso -o/tmp/homm2-iso
        cp -r /tmp/homm2-iso/Heroes2/ANIM "$out/"
      '';

  wrapper = writeShellScript "homm2" ''
    datadir="''${XDG_DATA_HOME:-$HOME/.local/share}/fheroes2"
    mkdir -p "$datadir"

    # Link game data directories
    for d in DATA MAPS MUSIC ANIM HEROES2; do
      if [ -d "${gameData}/$d" ] && ( [ ! -e "$datadir/$d" ] || [ -L "$datadir/$d" ] ); then
        ln -sfn "${gameData}/$d" "$datadir/$d"
      fi
    done

    exec ${lib.getExe fheroes2} "$@"
  '';
in
stdenvNoCC.mkDerivation {
  pname = "homm2";
  inherit (fheroes2) version;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    ln -s ${wrapper} $out/bin/homm2
  '';

  meta = {
    description = "Heroes of Might & Magic II Gold (via fheroes2)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "homm2";
  };
}
