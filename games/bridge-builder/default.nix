{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Bridge Builder (Chronic Logic 2000) freeware demo. The bbdemo.exe
  # mirrored on community sites (fun-motion.com, bridgebuilder-game.com)
  # is a Gentee-installer self-extractor (122 KiB PE32, "Gentee installer"
  # string in the stub), not the game itself — running it through Proton
  # presents a Windows installer wizard rather than starting Bridge
  # Builder. The installer has no documented silent flag and the Gentee
  # archive format isn't supported by 7z/innoextract/unar.
  #
  # This package ships a deterministic tar.zst of the post-install tree
  # baked once outside the Nix sandbox by driving bbdemo.exe through
  # xdotool under Xvfb+Wine, then stripped of installer debris
  # (uninstall.exe, uninstall.ini, Windows Start Menu shortcuts):
  #
  #   bridge.exe            — the actual game (120 KiB PE32)
  #   Font.bmp              — bitmap font texture
  #   level/level01..15.lvl — built-in puzzle levels (no level13/14 entry)
  #   1stplace.brg, 2ndplace.brg, level6.brg, level8.brg, level11.brg
  #                         — example solved bridges shipped with the game
  #   Bridge Builder.url, readme.txt
  #
  # Save bridges (*.brg) get written next to bridge.exe by the engine;
  # the fuse-overlayfs upper directory under $STROM_GAMEDIR captures them.
  src = fetchIpfs {
    cid = "bafkreifyyr4daukoyvdd23vmscqdv7prpeo2m65b6mrybnazsndqhicjxi";
    hash = "sha256-uMR4MFFOxUY9bqyQoDr98Xkdpnuh8yOAtBmTRwOgSbo=";
    name = "bridge-builder.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "bridge-builder";

  inherit src;

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
  '';

  runtime = "proton";
  executable = "bridge.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Bridge Builder (Chronic Logic 2000 freeware demo, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bridge-builder";
  };
}
