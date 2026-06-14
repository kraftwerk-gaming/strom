{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  src = fetchIpfs {
    cid = "QmbRZQvqyvxLaHvxt38ZQz4zN1q6zaEHBsADkYMnXqoXdy";
    fallbackUrl = "";
    hash = "sha256-sh6v7CMoORsgd0WGZnxiz9euGpjBcjzW7THr0KbF1H0=";
    name = "mina-the-hollower-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mina-the-hollower";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # AnkerGames layout: Mina the Hollower/{MinaTheHollower.exe,data/,...}.
  # Ships with a RUNE steam emu (steam_api64.dll + .rne + steam_emu.ini);
  # original Valve dll is backed up as steam_api64.dll.valve.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Mina the Hollower/"* "$out"/
  '';

  runtime = "proton";
  saveLocations = [ "AppData/Roaming/Yacht Club Games/Mina the Hollower" ];
  executable = "MinaTheHollower.exe";

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
    description = "Mina the Hollower (Yacht Club Games 2026, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "mina-the-hollower";
  };
}
