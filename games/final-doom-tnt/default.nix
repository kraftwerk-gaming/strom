{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gzdoom,
}:

let
  # Final Doom: TNT - Evilution (TeamTNT / id Software 1996). One of the
  # two standalone IWAD megawads shipped on the retail Final Doom CD.
  # TNT.WAD is a full Doom 2 replacement (IWAD, not PWAD) -- it does
  # not load against doom2.wad. Canonical v1.9 (Steam):
  #   size  : 18,195,736 bytes (1996-06-06)
  #   md5   : 4e158d9953c79ccf97bd0663244cc6b6
  #   sha1  : 9fbc66aedef7fe3bae0986cdb9323d2b8db4c9d3
  #   sha256: c0a9c29d023af2737953663d0e03177d9b7b7b64146c158dcc2a07f9ec18f353
  # See doomwiki.org/wiki/TNT.WAD. Driven by GZDoom from nixpkgs.
  wad = fetchIpfs {
    cid = "QmWxbxUpbCXFemuWhGqHhVJmtKQ4cfwmdaQyNNwwPHaLj5";
    fallbackUrl = "https://github.com/Akbar30Bill/DOOM_wads/raw/master/tnt.wad";
    hash = "sha256-wKnCnQI68nN5U2Y9DgMXfZt7e2QUbBWNzCoH+ewY81M=";
    name = "TNT.WAD";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "final-doom-tnt";

  ipfsSources = [ wad ];

  src = pkgs.runCommandLocal "final-doom-tnt-data" { } ''
    mkdir -p "$out"
    cp ${wad} "$out/TNT.WAD"
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
  # sandbox that resolves to ~/.strom/final-doom-tnt/.config/gzdoom via
  # the bind setup in mk-game. Saves and config persist there.
  runScript = ''
    mkdir -p "$STROM_GAMEDIR/.config/gzdoom"
    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
    export XDG_DATA_HOME="$STROM_GAMEDIR/.local/share"
    # Belt-and-suspenders: even if a future gamescope flag re-exposes the
    # Wayland socket, force SDL to use the XWayland path for input.
    export SDL_VIDEODRIVER=x11
    exec ${gzdoom}/bin/gzdoom \
      -fullscreen \
      -iwad "$GAMEDIR/TNT.WAD" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "Final Doom: TNT - Evilution (TeamTNT/id 1996, TNT.WAD via GZDoom)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "final-doom-tnt";
  };
}
