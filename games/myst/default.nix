{
  self,
  lib,
  pkgs,
  fetchIpfs,
  scummvm,
  p7zip,
}:

let
  # Myst: Masterpiece Edition (1999 Cyan/Ubisoft re-release of Myst with
  # 24-bit art and improved video). ScummVM's Mohawk engine supports it
  # under the "myst-me" target. The CD image at archive.org is the
  # original Windows install disc; the .DAT files (CHANNEL, CREDITS,
  # DUNNY, INTRO, MECHAN, MYST, SELEN, STONE, plus Help.dat) and the
  # QTW/ video tree live at the ISO root.
  src = fetchIpfs {
    cid = "QmYh8JKdbxsSaKiHKY284F4PrdCFnb3yJ22kvag7M5JN8X";
    fallbackUrl = "https://archive.org/download/myst-masterpiece-edition/MystMasterpieceEdition.iso";
    hash = "sha256-yCUIDjJyKlp71N4zDGbWBCp5BOA62zPsiG2iuiSlwlE=";
    name = "myst.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "myst";

  inherit src;

  nativeBuildInputs = [
    p7zip
  ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y -o"$TMPDIR/iso" "$src"
    cp "$TMPDIR/iso"/CHANNEL.DAT "$out"/
    cp "$TMPDIR/iso"/CREDITS.DAT "$out"/
    cp "$TMPDIR/iso"/DUNNY.DAT "$out"/
    cp "$TMPDIR/iso"/Help.dat "$out"/
    cp "$TMPDIR/iso"/INTRO.DAT "$out"/
    cp "$TMPDIR/iso"/MECHAN.DAT "$out"/
    cp "$TMPDIR/iso"/MYST.DAT "$out"/
    cp "$TMPDIR/iso"/SELEN.DAT "$out"/
    cp "$TMPDIR/iso"/STONE.DAT "$out"/
    cp -r "$TMPDIR/iso"/QTW "$out"/
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
    description = "Myst: Masterpiece Edition (1999 Cyan/Ubisoft, via ScummVM Mohawk)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "myst";
  };
}
