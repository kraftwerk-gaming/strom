{
  self,
  lib,
  pkgs,
  fetchIpfs,
  scummvm,
  gamescope,
  p7zip,
}:

let
  # Full Throttle (1995 LucasArts) SCUMM v6 CD release. The archive
  # ships an ISO9660 disc image (THROTTLE.iso) extracted from the
  # original CD; the SCUMM data files (FT.LA0 + FT.LA1) live under
  # Resource/, which ScummVM auto-detects as the "ft" target. Music
  # is iMUSE digital, no Red Book audio track to worry about.
  src = fetchIpfs {
    cid = "QmWDfCXN5oDmTUtDH3S9PyhLk5r5kLkmifvB4tDqhRpHNu";
    fallbackUrl = "https://archive.org/download/throttle_202510/THROTTLE.7z";
    hash = "sha256-BCdMinbQ34v4I+s1gOc6rqNyndlUw0ssC/m8BxjPD8I=";
    name = "full-throttle.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "full-throttle";

  inherit src;

  nativeBuildInputs = [
    p7zip
  ];

  # The 7z holds THROTTLE.iso (ISO9660). Extract the 7z, then pull
  # the Resource/ tree (FT.LA0, FT.LA1, etc.) out of the ISO so
  # ScummVM can auto-detect the game.
  buildScript = ''
    mkdir -p "$out"
    7z x -y -o"$TMPDIR/7z" "$src"
    7z x -y -o"$TMPDIR/iso" "$TMPDIR/7z/THROTTLE/THROTTLE.iso"
    cp -r "$TMPDIR/iso/Resource"/. "$out"/
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
    description = "Full Throttle (1995 LucasArts SCUMM CD edition, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "full-throttle";
  };
}
