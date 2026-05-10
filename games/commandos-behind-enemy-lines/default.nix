{
  self,
  lib,
  pkgs,
  fetchIpfs,
  bchunk,
  p7zip,
  unar,
  writeText,
}:

let
  # English Win95 retail BIN (multi-track CD with data on tracks 1+4 and
  # CD audio on tracks 2+3 — the game streams in-mission music from CD).
  src = fetchIpfs {
    cid = "QmPygowuCaS7xtfRTPLgYvybjD8u1oFDTvKbXVhwKHF1ij";
    fallbackUrl = "https://archive.org/download/Eidos_Commandos_Behind_Enemy_Lines_Win95_1998_Eng/Eidos-CommandosBehindEnemyLines-Win95.bin";
    hash = "sha256-yoQ0B5+qMGXL3YdBZlffpgXB2Ho45KF2ZOfOnhtLbEc=";
    name = "commandos-1-eng-win95.bin";
  };

  # Kruulos community "Ultimate Fix": patched comandos.exe (no disc check,
  # save/load + speed fixes) and a re-packaged WARGAME.DIR. Without this,
  # the retail game asks for a CD on every menu interaction.
  ultimateFix = fetchIpfs {
    cid = "QmYyWm3mZJew3jz3QPvWQQ7HUyf3rFbEC6Qo7TaPD3eS6b";
    fallbackUrl = "https://kruulos.org/gaming/Commandos_BEL_BCD_Ultimate_Fixes.rar";
    hash = "sha256-ec4nt5Di5j4oM1PZOzJr1uIT9uCohjQLu/GiP3p9N+c=";
    name = "commandos-bel-ultimate-fix.rar";
  };

  cue = writeText "commandos.cue" ''
    FILE "commandos-1-eng-win95.bin" BINARY
      TRACK 01 MODE1/2352
        INDEX 01 00:00:00
      TRACK 02 AUDIO
        INDEX 01 71:16:70
      TRACK 03 AUDIO
        INDEX 01 75:34:00
      TRACK 04 MODE1/2352
        INDEX 01 75:58:00
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "commandos-behind-enemy-lines";

  inherit src;

  ipfsSources = [
    src
    ultimateFix
  ];

  nativeBuildInputs = [
    bchunk
    p7zip
    unar
  ];

  buildScript = ''
    mkdir -p "$out" /tmp/c1
    # bchunk wants the cue and bin in the same dir with matching names.
    ln -s "$src" /tmp/c1/commandos-1-eng-win95.bin
    cp ${cue} /tmp/c1/commandos.cue
    bchunk /tmp/c1/commandos-1-eng-win95.bin /tmp/c1/commandos.cue /tmp/c1/track
    # Track 01 holds the COMANDOS install dir (1998 Pyro Studios kept the
    # Spanish folder names even in the English release). bchunk produces
    # an ISO whose header claims the full multi-track size, so 7z reports
    # an "Unexpected end of archive" even when extraction succeeds — ignore
    # the exit code and verify by checking the extracted dir exists.
    7z x -o/tmp/c1/iso /tmp/c1/track01.iso COMANDOS || true
    test -f /tmp/c1/iso/COMANDOS/Comandos.exe
    cp -r /tmp/c1/iso/COMANDOS/. "$out"/
    chmod -R u+w "$out"

    # Apply Kruulos Ultimate Fix: replace comandos.exe and WARGAME.DIR
    # so the game stops asking for the CD and works on modern Wine/Win.
    unar -q -o /tmp/c1/fix ${ultimateFix}
    fixdir=$(echo /tmp/c1/fix/Commandos*Ultimate*Fix*)
    cp "$fixdir/comandos.exe" "$out/Comandos.exe"
    cp "$fixdir/WARGAME.DIR" "$out/WARGAME.DIR"
  '';

  runtime = "proton";
  executable = "Comandos.exe";

  saveLocations = [ "Documents/Pyro Studios" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 800;
    nested-height = 600;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  meta = {
    description = "Commandos: Behind Enemy Lines (1998 Eidos / Pyro Studios, English Win95, via Proton + Kruulos Ultimate Fix)";
    longDescription = ''
      The game still pops an "insert CD" dialog on campaign start (intro
      video lookup); cancel proceeds straight to gameplay.
    '';
    platforms = [ "x86_64-linux" ];
    mainProgram = "commandos-behind-enemy-lines";
  };
}
