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
  # Indiana Jones and the Fate of Atlantis (1992 LucasArts), SCUMM v5
  # CD/talkie release: original ATLANTIS.000/001 data files plus
  # MONSTER.SOU (English voice acting) and the IMS music banks. The
  # archive ships everything under ATLANTIS/, which ScummVM auto-detects
  # as the "atlantis" target.
  src = fetchIpfs {
    cid = "QmQsVBJrAmzNf1dwuuB4X4N6ssuattvT5dkNetiQ2NSyUs";
    fallbackUrl = "https://archive.org/download/IndianaJones_Atlantis/ATLANTIS.zip";
    hash = "sha256-Dz/DlmQsgABp0xq5oIezFPG7FhLTesy+E7YBMhmslPA=";
    name = "indiana-jones-and-the-fate-of-atlantis.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "indiana-jones-and-the-fate-of-atlantis";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/ATLANTIS"/. "$out"/
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
    description = "Indiana Jones and the Fate of Atlantis (1992 LucasArts SCUMM CD talkie edition, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "indiana-jones-and-the-fate-of-atlantis";
  };
}
