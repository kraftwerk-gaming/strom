{
  self,
  lib,
  pkgs,
  fetchIpfs,
  scummvm,
  unzip,
}:

let
  # Sam & Max Hit the Road (1993 LucasArts, SCUMM engine).
  # The CD talkie release: English voice acting via monster.sou, with the
  # game data in samnmax.000 / samnmax.001 / samnmax.rsc. ScummVM
  # auto-detects the SCUMM game from these files. This archive.org upload
  # is a plain data-files zip (not a CD redump), so the tree is copied
  # directly.
  src = fetchIpfs {
    cid = "QmdZwdf2e9GhA9riQaF8FZRUq9Yu7HiJvYYXaWVvbYCPsy";
    fallbackUrl = "https://archive.org/download/sammax_dos/samnmax.zip";
    hash = "sha256-OFxqId/PGTQfL70curvSwperE8c0YfgnkFrd20DnOmw=";
    name = "sam-max-hit-the-road.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sam-max-hit-the-road";

  inherit src;

  nativeBuildInputs = [
    unzip
  ];

  # The upload is a plain zip of the CD data files (samnmax.000/.001/.rsc,
  # monster.sou), so just unpack the tree so ScummVM can auto-detect it.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
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
    description = "Sam & Max Hit the Road (1993 LucasArts CD talkie edition, via ScummVM)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sam-max-hit-the-road";
  };
}
