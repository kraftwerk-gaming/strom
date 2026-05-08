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
  # Simon the Sorcerer (Adventure Soft, 1993). The 1996 CD/Windows
  # English re-release: same data files as the floppy version plus the
  # talkie's voice file (simon.fla, ~62 MB) and SFX banks (SFXXXX*).
  # ScummVM auto-detects this as "agos:simon1 Simon the Sorcerer
  # (CD/Windows/English)" and plays it natively.
  src = fetchIpfs {
    cid = "QmdByyMGo1pcNU7UQq2Y96FBeDGvF15gXQNDieV6xLy8fY";
    fallbackUrl = "https://archive.org/download/msdos_Simon_the_Sorcerer_1993/Simon_the_Sorcerer_1993.zip";
    hash = "sha256-QEChJPYZiM+j23Em381Hw8zYqlAtGc1+pLSosXJhCY8=";
    name = "simon-the-sorcerer-1993.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "simon-the-sorcerer";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/simon1"/. "$out"/
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
    description = "Simon the Sorcerer (Adventure Soft, 1993 CD/Windows English talkie, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "simon-the-sorcerer";
  };
}
