{
  self,
  lib,
  pkgs,
  fetchIpfs,
  scummvm,
  unzip,
}:

let
  # Indiana Jones and the Last Crusade: The Graphic Adventure
  # (1989 Lucasfilm Games), SCUMM v3 floppy release. The archive
  # ships the .lfl data files (00.lfl..NN.lfl) under IndyCru/, which
  # ScummVM auto-detects as the "indy3" target.
  src = fetchIpfs {
    cid = "QmXLWtUZvvHqHRCn2thpaWZVcCncCgM6RpVeFmxazrG8HK";
    fallbackUrl = "https://archive.org/download/msdos_Indiana_Jones_and_The_Last_Crusade_1989/Indiana_Jones_and_The_Last_Crusade_1989.zip";
    hash = "sha256-/Z1GoObeRae7i0O9tsX0c0syxEohCwIiuC8s4y4sOrY=";
    name = "indiana-jones-and-the-last-crusade-the-graphic-adventure.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "indiana-jones-and-the-last-crusade-the-graphic-adventure";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cp -r "$TMPDIR/zip/IndyCru"/. "$out"/
  '';

  runtime = "native";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  runScript = ''
    mkdir -p "$STROM_GAMEDIR/save"
    exec ${scummvm}/bin/scummvm \
      --fullscreen \
      --path="$GAMEDIR" \
      --savepath="$STROM_GAMEDIR/save" \
      --auto-detect
  '';

  meta = {
    description = "Indiana Jones and the Last Crusade: The Graphic Adventure (1989 Lucasfilm SCUMM floppy, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "indiana-jones-and-the-last-crusade-the-graphic-adventure";
  };
}
