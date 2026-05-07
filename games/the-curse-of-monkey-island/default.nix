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
  # The Curse of Monkey Island (1997 LucasArts), 2-CD redump (PC EU
  # release). Both discs share an INSTALL/ + RESOURCE/ tree; ScummVM
  # wants the union of the two RESOURCE/ folders. Disc 1 ships
  # MUSDISK1.BUN / VOXDISK1.BUN plus the early-game .SAN videos; disc 2
  # ships MUSDISK2.BUN / VOXDISK2.BUN, the late-game .SAN videos, and
  # the actual game executable CURSE.EXE. The COMI engine is well
  # supported in ScummVM (--auto-detect picks it up by data fingerprint).
  disc1 = fetchIpfs {
    cid = "QmNb8LBXZ9LHKQSGmAgHSDZ6chKV1ybVHGDDh41tX1SJyM";
    fallbackUrl = "https://archive.org/download/monkey-3-1_20251027/MONKEY3_1.iso";
    hash = "sha256-iaa/1SnjIr78ZtjGZobNYIQhZcY7IQrfbfdRMvg2if4=";
    name = "the-curse-of-monkey-island-disc1.iso";
  };
  disc2 = fetchIpfs {
    cid = "QmYDMzNg1iLCF83UXfcuFhyGu6UQ6fEq6d8h4GVSv9hTVS";
    fallbackUrl = "https://archive.org/download/monkey-3-1_20251027/MONKEY3_2.iso";
    hash = "sha256-PWvcLNoYiev1wpyt9hHCH8f5lRBRzd6zUXvyKHd6u20=";
    name = "the-curse-of-monkey-island-disc2.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-curse-of-monkey-island";

  src = disc1;

  ipfsSources = [
    disc1
    disc2
  ];

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out/RESOURCE"
    # COMI.LA0 is the SCUMM index (76 KiB, identical on both discs).
    # COMI.LA1 / COMI.LA2 are the per-disc data archives, both required
    # by ScummVM (game id "scumm:comi" detects on COMI.LA0). Audio /
    # video bundles (MUSDISK*.BUN, VOXDISK*.BUN, *.SAN) live under
    # RESOURCE/ on each disc; ScummVM reads from both.
    7z x -y -o"$TMPDIR/d1" ${disc1} 'RESOURCE/*' 'COMI.LA0' 'COMI.LA1'
    7z x -y -o"$TMPDIR/d2" ${disc2} 'RESOURCE/*' 'COMI.LA2'
    cp -r "$TMPDIR/d1/RESOURCE"/. "$out/RESOURCE"/
    cp -r "$TMPDIR/d2/RESOURCE"/. "$out/RESOURCE"/
    cp "$TMPDIR/d1/COMI.LA0" "$TMPDIR/d1/COMI.LA1" "$out"/
    cp "$TMPDIR/d2/COMI.LA2" "$out"/
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
    description = "The Curse of Monkey Island (1997 LucasArts, 2-CD PC EU release, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-curse-of-monkey-island";
  };
}
