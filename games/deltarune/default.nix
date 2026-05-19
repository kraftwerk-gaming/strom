{
  self,
  lib,
  pkgs,
  fetchIpfs,
  stdenv,
}:

let
  # LinuxRuleZ-style YAD self-extracting installer wrapping a Windows
  # build of DELTARUNE (Toby Fox, 2018-2025, chapters 1-4). The .sh
  # tail is an xz-compressed tarball of `arcsz` bytes; inside it the
  # full payload tree is `DELTARUNE/game/prefix/drive_c/game/`, which
  # contains the GameMaker runner (DELTARUNE.exe + data.win + chapter
  # data dirs + music). The repack also ships its own bundled wine and
  # a portable prefix under `DELTARUNE/game/{wine,prefix}/`; we discard
  # those and let Proton + this repo's `mk-game.nix` manage the prefix
  # ourselves so the game integrates with saveLocations + gamescope.
  installer = fetchIpfs {
    cid = "QmSSr7w3G9i3EidAK51sjnpGUuDEX55q2cp3FwLefQN2UV";
    fallbackUrl = "https://archive.org/download/deltarune_20250916/DELTARUNE.sh";
    hash = "sha256-Koq80dStkCpX+Hk058rK4VVGPvwPBU7s40emZEneID0=";
    name = "deltarune-linux.sh";
  };

  arcsz = 928825096;

  gameData = stdenv.mkDerivation {
    pname = "deltarune-data";
    version = "0.0.0";

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tail -c ${toString arcsz} ${installer} | xzcat \
        | tar -xf - --strip-components=5 \
            'DELTARUNE/game/prefix/drive_c/game'
      cp -r ./* "$out"/
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "deltarune";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "proton";
  executable = "DELTARUNE.exe";
  saveLocations = [ "AppData/Local/DELTARUNE" ];

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
    description = "DELTARUNE (Toby Fox 2018-2025, chapters 1-4, GameMaker / Windows via Proton; LinuxRuleZ repack)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "deltarune";
  };
}
