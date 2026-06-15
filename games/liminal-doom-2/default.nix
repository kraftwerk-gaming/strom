{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gzdoom,
}:

let
  # Liminal Doom 2: Crossing The Threshold (dashlet, 2024) -- a Cacoward-
  # winning MBF21 megawad of liminal-space horror maps. It is a PWAD: it
  # loads on top of the commercial DOOM2.WAD IWAD, which we pull from the
  # same already-pinned asset the doom-ii game uses. Driven by GZDoom from
  # nixpkgs. The idgames distribution is a zip containing ld2.wad (~23 MiB);
  # we fetch the zip and extract the wad at build time.
  #   idgames: levels/doom2/Ports/j-l/ld2 (id 21233)
  ld2 = fetchIpfs {
    cid = "QmcYboes353EtSS4xYFtAgzcKDEybEaioRrLBsbk3d2WiV";
    fallbackUrl = "https://www.gamers.org/pub/idgames/levels/doom2/Ports/j-l/ld2.zip";
    hash = "sha256-Y06LKMjrvkYd7vCgXsGCm2mUgPspx06tFA8wG/rakRg=";
    name = "ld2.zip";
  };

  # DOOM II: Hell on Earth IWAD (id Software 1994) -- the same asset and CID
  # already pinned by the doom-ii game. Liminal Doom 2 is a Doom II PWAD and
  # requires it.
  doom2 = fetchIpfs {
    cid = "QmbvTqMatBt2tRcuM461BbCUdrf2kzL6hMSNUtGP4amkJc";
    fallbackUrl = "https://archive.org/download/DOOM2IWADFILE/DOOM2.WAD";
    hash = "sha256-XnAcgGqNOgNwD3/vl7etYtCu1Q/SQN+sJs3zmsPQqNU=";
    name = "DOOM2.WAD";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "liminal-doom-2";

  ipfsSources = [
    ld2
    doom2
  ];

  src = pkgs.runCommandLocal "liminal-doom-2-data" { nativeBuildInputs = [ pkgs.unzip ]; } ''
    mkdir -p "$out"
    cp ${doom2} "$out/DOOM2.WAD"
    unzip -o ${ld2} ld2.wad -d "$out"
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
      # Intentionally NO --expose-wayland: see doom-ii / final-doom -- the
      # nested-Wayland relative-pointer protocol breaks gzdoom mouse-look.
      # The XWayland fallback (no --expose-wayland, --force-grab-cursor) works.
      "--force-grab-cursor" = true;
    };
  };

  # GZDoom defaults its config dir to ~/.config/gzdoom; under our bwrap
  # sandbox that resolves to ~/.strom/liminal-doom-2/.config/gzdoom via the
  # bind setup in mk-game. Saves and config persist there.
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
      -file "$GAMEDIR/ld2.wad" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "Liminal Doom 2: Crossing The Threshold (dashlet 2024, MBF21 PWAD via GZDoom)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "liminal-doom-2";
  };
}
