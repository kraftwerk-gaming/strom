{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gzdoom,
}:

let
  # Unloved (Paul Schneider 2010/2016) is a GZDoom horror mod for DOOM II.
  # It is a PWAD (unloved.pk3, maps map01-map05) that loads ON TOP of the
  # commercial DOOM2.WAD IWAD -- it is NOT standalone. We drive both with
  # the open-source GZDoom engine from nixpkgs:
  #   gzdoom -iwad DOOM2.WAD -file unloved.pk3
  #
  # DOOM2.WAD: same commercial IWAD asset shipped by games/doom-ii.
  wad = fetchIpfs {
    cid = "QmbvTqMatBt2tRcuM461BbCUdrf2kzL6hMSNUtGP4amkJc";
    fallbackUrl = "https://archive.org/download/DOOM2IWADFILE/DOOM2.WAD";
    hash = "sha256-XnAcgGqNOgNwD3/vl7etYtCu1Q/SQN+sJs3zmsPQqNU=";
    name = "DOOM2.WAD";
  };

  # unloved.pk3 from the Doomworld /idgames archive (unloved.zip). The
  # archive ships the pk3 inside a zip alongside the text files; we pin the
  # bare pk3 to IPFS, so there is no single stable direct URL for just the
  # pk3 (only the zip) -- fallbackUrl is empty, IPFS is the source of truth.
  #   idgames: levels/doom2/Ports/s-u/unloved.zip
  pk3 = fetchIpfs {
    cid = "QmW3M6hLUCYsHmYVzcnytnrKe4qiPPcPT2Cn2NdQyXNuub";
    fallbackUrl = "";
    hash = "sha256-kNrRdN/61XPoFo7tfwraFRK/gNSwWcoCTDRRVKhXqxM=";
    name = "unloved.pk3";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "unloved";

  ipfsSources = [
    wad
    pk3
  ];

  src = pkgs.runCommandLocal "unloved-data" { } ''
    mkdir -p "$out"
    cp ${wad} "$out/DOOM2.WAD"
    cp ${pk3} "$out/unloved.pk3"
  '';

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "custom";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      # Intentionally NO --expose-wayland: with it, gzdoom's SDL2 backend
      # picks up gamescope's nested Wayland socket and uses the relative-
      # pointer protocol, which under gamescope-nested delivers sustained
      # Y deltas -- the player view pitches up the moment you touch the
      # mouse. Without it, SDL falls back to XWayland inside gamescope,
      # where the legacy X11 input path works correctly. See master commit
      # 6b0825c (doom) / 864b62d (doom-ii) for the same fix.
      "--force-grab-cursor" = true;
    };
  };

  # GZDoom defaults its config dir to ~/.config/gzdoom; under our bwrap
  # sandbox that resolves to ~/.strom/unloved/.config/gzdoom via the bind
  # setup in mk-game. Saves and config persist there.
  runScript = ''
    mkdir -p "$STROM_GAMEDIR/.config/gzdoom"
    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
    export XDG_DATA_HOME="$STROM_GAMEDIR/.local/share"
    # Belt-and-suspenders: even if a future gamescope flag re-exposes the
    # Wayland socket, force SDL to use the XWayland path for input.
    export SDL_VIDEODRIVER=x11
    exec ${gzdoom}/bin/gzdoom \
      -fullscreen \
      -iwad "$GAMEDIR/DOOM2.WAD" \
      -file "$GAMEDIR/unloved.pk3" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "Unloved (Paul Schneider 2010, GZDoom horror mod for DOOM II)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "unloved";
  };
}
