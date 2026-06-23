{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Katamari Damacy REROLL (Bandai Namco / MONKEYCRAFT, 2018) -- the PC
  # remaster of the 2004 PS2 game. Windows-only Unity 2019 (mono) title,
  # no native Linux build, so runtime = "proton". ProtonDB rates it
  # Gold/Platinum.
  #
  # SOURCE: archive.org item "katamari-damacy-reroll", a single
  # pre-installed RAR5 (store/uncompressed, ~1.79 GiB). The archive is
  # triple-nested under three identical Katamari.Damacy.REROLL.v2019.01.31/
  # levels; the game root holds katamari.exe + katamari_Data/ +
  # UnityPlayer.dll. The repack already ships a Goldberg/steam-emu
  # steam_api64.dll (+ steam_api.dll), so the game starts offline without
  # Steam -- no gbe_fork swap needed at build time.
  src = fetchIpfs {
    cid = "QmUGnYJKJB5txWFnCWCbqsB1UQpyfWGeTMoMPKxxYGV7Wx";
    fallbackUrl = "https://archive.org/download/katamari-damacy-reroll/Katamari-Damacy-REROLL.rar";
    hash = "sha256-BtcpPG8X8MpabLYPYnC20uGzIueGk3q1lfjbtEaDOzQ=";
    name = "Katamari-Damacy-REROLL.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "katamari-damacy-reroll";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -q -D -o "$TMPDIR/extract" "$src"
    # Flatten past the triple-nested Katamari.Damacy.REROLL.v2019.01.31/
    # wrapper dirs down to the game root (the one holding katamari.exe).
    root=$(dirname "$(find "$TMPDIR/extract" -name katamari.exe -print -quit)")
    cp -a "$root"/. "$out"/

    # Drop the repack ad junk and the Unity crash reporter: `proton
    # waitforexitandrun` waits for every wine process to exit, so a
    # lingering UnityCrashHandler wedges proton/gamescope open after quit.
    rm -f "$out"/UnityCrashHandler*.exe
    find "$out" -maxdepth 1 \( -iname '*.url' -o -iname '*READ ME*.txt' \) -delete
  '';

  runtime = "proton";
  executable = "katamari.exe";

  # Unity LocalLow tree (company / product from katamari_Data/app.info).
  saveLocations = [ "AppData/LocalLow/BANDAI NAMCO Entertainment/katamaridamacy" ];

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
    description = "Katamari Damacy REROLL (Bandai Namco 2018 remaster, Unity / Windows via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "katamari-damacy-reroll";
  };
}
