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
  # Beneath a Steel Sky (1994 Revolution Software). Revolution released
  # the CD edition as freeware in 2003; ScummVM hosts the data files at
  # downloads.scummvm.org. The CD release ships speech (sky.cpt) and the
  # game data files (sky.dnr, sky.dsk), all of which ScummVM auto-detects
  # as the "sky" target.
  src = fetchIpfs {
    cid = "Qmd9tAn6ff6fooW59N6LZGc9hJaCQMenQfBjFUj4gToFsC";
    fallbackUrl = "https://downloads.scummvm.org/frs/extras/Beneath%20a%20Steel%20Sky/bass-cd-1.2.zip";
    hash = "sha256-UyCblADqtv1/pxUYsvNXyN51z+qlulcCRXWrecyXRZM=";
    name = "beneath-a-steel-sky.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "beneath-a-steel-sky";

  inherit src;

  nativeBuildInputs = [
    unzip
  ];

  # The zip ships sky.dnr, sky.dsk, sky.cpt under bass-cd-1.2/.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/bass-cd-1.2"/. "$out"/
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
    description = "Beneath a Steel Sky (1994 Revolution Software CD freeware, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "beneath-a-steel-sky";
  };
}
