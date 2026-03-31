{
  lib,
  pkgs,
  fetchurl,
  p7zip,
}:

let
  disc1 = fetchurl {
    url = "https://archive.org/download/xenogears-USA.-7z/Xenogears%20%28Disc%201%29.7z";
    hash = "sha256-36cmJhQcuXcGg7A/yvPaxuFEQEYi/BlbgpNqFxqfyik=";
    name = "xenogears-disc1.7z";
  };

  disc2 = fetchurl {
    url = "https://archive.org/download/xenogears-USA.-7z/Xenogears%20%28Disc%202%29.7z";
    hash = "sha256-kF513kDCTNAwVxpQwKFqwkSiU612qdfdB2oLfJMmOu4=";
    name = "xenogears-disc2.7z";
  };

  psxBios7z = fetchurl {
    url = "https://archive.org/download/psx-usa-jap-eu_bios/psx-usa-jap-eu_bios/scph1001.7z";
    hash = "sha256-IFyuviXa2nizXdQMiQDClqDT1qCNRtMnXllQtgyDxv0=";
    name = "scph1001.7z";
  };

  gameDiscs = pkgs.runCommandLocal "xenogears-discs" { nativeBuildInputs = [ p7zip ]; } ''
    mkdir -p $out
    7z x ${disc1} -o$out -aoa
    7z x ${disc2} -o$out -aoa
    rm -f $out/readme.html
  '';

  biosDir = pkgs.runCommandLocal "psx-bios" { nativeBuildInputs = [ p7zip ]; } ''
    mkdir -p $out
    7z x ${psxBios7z} -o$out -aoa
    mv $out/scph1001.bin $out/scph5501.bin
  '';

  swanstation = pkgs.libretro.swanstation;

  retroarch = pkgs.retroarch.withCores (_: [ swanstation ]);

  retroCfg = pkgs.writeText "retroarch.cfg" ''
    system_directory = "${biosDir}"
    savefile_directory = "%s/saves"
    savestate_directory = "%s/states"
    input_autodetect_enable = "true"
    input_joypad_driver = "sdl2"
    video_driver = "vulkan"
    video_fullscreen = "false"
    video_windowed_fullscreen = "false"
    menu_driver = "ozone"
    pause_nonactive = "false"
  '';
in
pkgs.writeShellApplication {
  name = "xenogears";
  runtimeInputs = [ retroarch pkgs.gamescope ];
  text = ''
    DATADIR="''${HOME:-.}/.strom/xenogears"
    mkdir -p "$DATADIR/saves" "$DATADIR/states"

    # Write config
    sed "s|%s|$DATADIR|g" ${retroCfg} > "$DATADIR/retroarch.cfg"

    exec gamescope -W 1920 -H 1080 -w 960 -h 720 -- \
      env QT_QPA_PLATFORM=xcb retroarch \
        --appendconfig "$DATADIR/retroarch.cfg" \
        -L ${swanstation}/lib/retroarch/cores/swanstation_libretro.so \
        "${gameDiscs}/Xenogears (Disc 1).cue"
  '';
}
