{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gzdoom,
}:

let
  # DOOM II: Hell on Earth IWAD (id Software 1994). MyHouse.wad is a
  # Doom 2 PWAD/total-conversion -- it loads against DOOM2.WAD, which it
  # does not replace. Reuse the same already-pinned DOOM2.WAD asset the
  # doom-ii game ships.
  iwad = fetchIpfs {
    cid = "QmbvTqMatBt2tRcuM461BbCUdrf2kzL6hMSNUtGP4amkJc";
    fallbackUrl = "https://archive.org/download/DOOM2IWADFILE/DOOM2.WAD";
    hash = "sha256-XnAcgGqNOgNwD3/vl7etYtCu1Q/SQN+sJs3zmsPQqNU=";
    name = "DOOM2.WAD";
  };

  # MyHouse.wad (Veddge, 2023) -- the non-euclidean horror mod. Ships as
  # myhouse.pk3, a GZDoom pk3 (zip) requiring modern GZDoom features.
  # Loaded as a -file PWAD on top of DOOM2.WAD. We use the maintained
  # 2025-04-28 cut (md5 ee159a727d2ca5784cd298e570c93467): the original
  # 2023-04-16 build's ZSCRIPT (`weapons.push(Int(weap))`) fails to
  # compile on GZDoom 4.14.2 ("Cannot convert to name"); the 2025 update
  # reworks that code and loads cleanly. Same mod, modern-GZDoom-safe.
  pk3 = fetchIpfs {
    cid = "QmSpTzD3sLHw9FqECyjDBxb46fLMxHnwnHGiKyBwgCcmLs";
    fallbackUrl = "https://archive.org/download/myhouse-versions/myhouse-20250428.pk3";
    hash = "sha256-RGZfcyriy4Hp1FAHlJ7wATg5cPhRPuegEPQysFyzIh4=";
    name = "myhouse.pk3";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "myhouse-wad";

  ipfsSources = [
    iwad
    pk3
  ];

  src = pkgs.runCommandLocal "myhouse-wad-data" { } ''
    mkdir -p "$out"
    cp ${iwad} "$out/DOOM2.WAD"
    cp ${pk3} "$out/myhouse.pk3"
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
      # Intentionally NO --expose-wayland: see doom-ii / final-doom --
      # gamescope's nested-Wayland relative-pointer protocol breaks
      # gzdoom mouse-look. The XWayland fallback (no --expose-wayland,
      # --force-grab-cursor) works.
      "--force-grab-cursor" = true;
    };
  };

  # GZDoom defaults its config dir to ~/.config/gzdoom; under our bwrap
  # sandbox that resolves to ~/.strom/myhouse-wad/.config/gzdoom via the
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
      -file "$GAMEDIR/myhouse.pk3" \
      +logfile "$STROM_GAMEDIR/.config/gzdoom/console.log"
  '';

  meta = {
    description = "MyHouse.wad (Veddge 2023, non-euclidean horror mod; myhouse.pk3 + DOOM2.WAD via GZDoom)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "myhouse-wad";
  };
}
