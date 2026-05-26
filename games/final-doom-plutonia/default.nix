{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gzdoom,
}:

let
  # Final Doom: The Plutonia Experiment (Dario & Milo Casali / id 1996).
  # One of the two standalone IWAD megawads shipped on the retail Final
  # Doom CD. PLUTONIA.WAD is a full Doom 2 replacement (IWAD, not PWAD)
  # -- it does not load against doom2.wad. Canonical v1.9:
  #   size  : 17,420,824 bytes (1996-06-07)
  #   md5   : 75c8cf89566741fa9d22447604053bd7
  #   sha1  : 90361e2a538d2388506657252ae41aceeb1ba360
  #   sha256: a83b00c636fa3308286e76b1b3153fc14507caf994b0450770421260b08efed8
  # See doomwiki.org/wiki/PLUTONIA.WAD. Driven by GZDoom from nixpkgs.
  wad = fetchIpfs {
    cid = "QmVEZYkuHDHZkYhpUkhefe9WdWYmyFBpM5oF2fSbYrwXXT";
    fallbackUrl = "https://github.com/Akbar30Bill/DOOM_wads/raw/master/plutonia.wad";
    hash = "sha256-qDsAxjb6MwgobnaxsxU/wUUHyvmUsEUHcEISYLCO/tg=";
    name = "PLUTONIA.WAD";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "final-doom-plutonia";

  ipfsSources = [ wad ];

  src = pkgs.runCommandLocal "final-doom-plutonia-data" { } ''
    mkdir -p "$out"
    cp ${wad} "$out/PLUTONIA.WAD"
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
      # Intentionally NO --expose-wayland: see master commit 6b0825c
      # (doom) / 864b62d (doom-ii) -- gamescope's nested-Wayland
      # relative-pointer protocol breaks gzdoom mouse-look. The XWayland
      # fallback (no --expose-wayland, --force-grab-cursor) works.
      "--force-grab-cursor" = true;
    };
  };

  # GZDoom defaults its config dir to ~/.config/gzdoom; under our bwrap
  # sandbox that resolves to ~/.strom/final-doom-plutonia/.config/gzdoom
  # via the bind setup in mk-game. Saves and config persist there.
  runScript = ''
    mkdir -p "$STROM_GAMEDIR/.config/gzdoom"
    export XDG_CONFIG_HOME="$STROM_GAMEDIR/.config"
    export XDG_DATA_HOME="$STROM_GAMEDIR/.local/share"
    # Belt-and-suspenders: even if a future gamescope flag re-exposes the
    # Wayland socket, force SDL to use the XWayland path for input.
    export SDL_VIDEODRIVER=x11
    exec ${gzdoom}/bin/gzdoom \
      -fullscreen \
      -iwad "$GAMEDIR/PLUTONIA.WAD" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "Final Doom: The Plutonia Experiment (Casali/id 1996, PLUTONIA.WAD via GZDoom)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "final-doom-plutonia";
  };
}
