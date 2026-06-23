{
  self,
  fetchIpfs,
  lib,
  love,
  pkgs,
}:

let
  # The original Flappy Bird (.Gears, 2013) is a mobile-only title with no
  # official PC release. This packages "Flöppy Bird" v0.6 by NiroUwU
  # (github.com/nirokay/FloppyBird), a faithful open-source Flappy Bird clone
  # built on the LÖVE (Love2D) 11.x engine. Distributed as a portable `.love`
  # archive (a zip containing main.lua + conf.lua + assets), run with
  # pkgs.love. Native Linux, no Proton needed.
  #
  # Source: GitHub release asset floppybird_0.6.love (2,148,650 bytes).
  game = fetchIpfs {
    cid = "QmS16Ytszjha3zfKfUV6kgMcLDvKwUgCgDqN9Q5gkPEnEd";
    fallbackUrl = "https://github.com/nirokay/FloppyBird/releases/download/v0.6/floppybird_0.6.love";
    hash = "sha256-7MVJEe2KptDUN9/VUAOn5ZRCrZYVE3MWrIYRuWeLt8I=";
    name = "floppybird_0.6.love";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "flappy-bird";

  ipfsSources = [ game ];
  src = game;

  buildScript = ''
    mkdir -p "$out"
    cp ${game} "$out/floppybird.love"
  '';

  runtime = "native";

  runScript = ''
    exec ${lib.getExe love} "$STROM_OVERLAY/floppybird.love"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1280;
    nested-height = 720;
    flags."--expose-wayland" = true;
  };

  # LÖVE writes saves to $XDG_DATA_HOME/love/<identity> (or
  # ~/.local/share/love/<identity>). conf.lua sets t.identity =
  # "nirouwu.floppybird". The native runtime binds $HOME -> $STROM_GAMEDIR,
  # so this persists to ~/.strom/flappy-bird/ across overlay/prefix resets.
  saveLocations = [ ".local/share/love/nirouwu.floppybird" ];

  meta = {
    description = "Flappy Bird (Flöppy Bird, faithful Love2D clone by NiroUwU, native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "flappy-bird";
  };
}
