{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  src = fetchIpfs {
    cid = "QmZxtbLWyArTEGhyotaLjHjypsbrFczPmGx2X5ZoYgmGkN";
    fallbackUrl = "";
    hash = "sha256-xgg89huU4UsS/e8CisPe6cSwL2x94JNEmnGgrRbyUGc=";
    name = "routine-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "routine";

  inherit src;

  nativeBuildInputs = [ _7zz ];

  # AnkerGames zip layout: Routine/{Routine.exe (UE5 bootstrapper),
  # Routine/Binaries/Win64/Routine-Win64-Shipping.exe, Engine/, ...}.
  # The archive is zstd-compressed (Info-ZIP `unzip` exits 81 on it), so
  # extract with 7zz. This is the RUNE release: ships its own Steam emulator
  # (Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_emu.ini,
  # AppId 606160) so Steamworks init succeeds offline with no gbe_fork swap.
  buildScript = ''
    mkdir -p "$out"
    7zz x -bso0 -bsp0 "$src" -o"$TMPDIR/extract" 'Routine/*'
    cp -r "$TMPDIR/extract/Routine/." "$out"/
    chmod -R u+w "$out"
  '';

  runtime = "proton";
  saveLocations = [
    # UE5 SaveGames slot
    "AppData/Local/Routine/Saved/SaveGames"
    # RUNE emulator's Steam-cloud emulation root (steam_emu.ini)
    "Public/Documents/Steam/RUNE/606160"
  ];
  executable = "Routine.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "ROUTINE (Lunar Software / Raw Fury 2025, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "routine";
  };
}
