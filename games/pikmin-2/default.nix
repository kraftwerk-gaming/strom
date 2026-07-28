{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Pikmin 2 (USA), GameCube 2004 original - NOT the 2009 Wii "New Play
  # Control!" port. Redump-verified dump from the "GameCube Redump 2024"
  # set: disc ID GPVE01, revision 0, region NTSC-U, internal name
  # "PIKMIN2 for GAMECUBE", disc SHA-1
  # 63a68c656d654388e096d27a768e85823dcf3327 (confirmed with
  # `dolphin-tool header/verify`).
  #
  # The set distributes each title as a TorrentZip'd RVZ (Dolphin's own
  # lossless container, 910867284 bytes / 869 MiB), so the FOD is the zip
  # and the build unpacks it. Dolphin loads .rvz natively; it is stored
  # as-is rather than recompressed to another container.
  zip = fetchIpfs {
    cid = "QmZ59GJmiHCoNhYFPjwKSPARSoyEeXDDnLYK8NC2fStkTo";
    fallbackUrl = "https://archive.org/download/GameCube-Redump-2024-Individual-Games-Part2/Pikmin%202%20%28USA%29.zip";
    hash = "sha256-7FlhUcjWG+fdLpu26bI/Vi8oIc23SFZUQ3U8r6Ht2No=";
    name = "pikmin-2.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pikmin-2";

  ipfsSources = [ zip ];
  src = zip;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR"
    mv "$TMPDIR/Pikmin 2 (USA).rvz" "$out/pikmin-2.rvz"
  '';

  runtime = "dolphin";
  executable = "pikmin-2.rvz";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
    };
  };

  meta = {
    description = "Pikmin 2 (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pikmin-2";
  };
}
