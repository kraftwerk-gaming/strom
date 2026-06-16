{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Tom Clancy's Splinter Cell: Chaos Theory (Ubisoft Montreal 2005, Unreal
  # Engine 2.5). No GOG release exists (Ubisoft never relisted it digitally),
  # so the source is the DODI repack: a customised Inno Setup 5.5 loader
  # (Setup.exe) plus a single FreeArc payload (data1.dd) compressed with the
  # CLS "lolz" codec (cls-lolz_x86/x64 external compressors driven through
  # ISDone.dll/unarc.dll). innoextract pulls the Inno tree but not the
  # FreeArc payload, and ISDone deadlocks under Proton's wine, so the install
  # is baked once on the host -- the data1.dd FreeArc archive is extracted
  # directly with FreeArc's Arc.exe plus the repack's own cls-lolz codec
  # plugins (bypassing the buggy ISDone GUI) -- and the resulting game tree is
  # pinned as a deterministic tar.zst. The repack ships DRM-stripped (the
  # uplay activation layer is a no-op stub); the playable tree is
  # System/splintercell3.exe over Data/ (Maps/Sounds/Textures/Videos).
  #
  # SplinterCell3.ini ships with ShaderModel=1 (the SM1.1 D3D9 renderer path,
  # not the SM3.0 path that black-screens on modern stacks) and
  # FullscreenViewport pinned to 1920x1080 at bake time, so the engine boots
  # straight into the menu under DXVK without a renderer downgrade.
  src = fetchIpfs {
    cid = "QmZvjRD1KbdzkjBAbkAM7vnk8HweuEY5nUQnYVuAWZkyNd";
    fallbackUrl = "";
    hash = "sha256-racveSdirhoPPdvivcHkXcI6qTDiJz2vigHp+cGr0SM=";
    name = "scct-dodi.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "tom-clancys-splinter-cell-chaos-theory";

  inherit src;
  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper: the UE2.5 engine
  # writes profile/save data under System/ (SaveGames, *User.ini) next to its
  # binary, not under drive_c/users/steamuser/...
  saveLocations = [ ];
  executable = "System/splintercell3.exe";

  # Unreal Engine 2.5 resolves SplinterCell3.ini / its config tree relative to
  # the current working directory, not the binary. mk-game's inner script cds
  # to $GAMEDIR (the overlay root), one level above System/, so the engine
  # would bail on a missing ini. Cd into System/ before exec (same idiom as
  # the SWAT 4 sibling).
  preRun = ''
    cd "$GAMEDIR/System"
  '';

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
    description = "Tom Clancy's Splinter Cell: Chaos Theory (Ubisoft Montreal 2005, Unreal Engine 2.5, DODI repack, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "tom-clancys-splinter-cell-chaos-theory";
  };
}
