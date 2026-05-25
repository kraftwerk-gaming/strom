{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  stdenv,
}:

let
  # Phoenix Games Lab "LinuxRuleZ!" repack of Dome Keeper v4.2.1 + Pioneer
  # Pack DLC. The .sh is a YAD self-extracting installer: 0..(total-arcsz)
  # is the YAD shell-script preamble, then xz-compressed tar payload of
  # `arcsz` bytes at the tail. The script's arcsz variable on line ~95
  # records the payload size; total - arcsz gives the script header size.
  # For this build: arcsz = 680_326_620, total = 681_655_338, so the xz
  # payload starts at offset 1_328_718. The xz unpacks to:
  #   Dome Keeper/game/domekeeper.x86_64  (Godot 4 binary)
  #   Dome Keeper/game/domekeeper.pck
  #   Dome Keeper/game/libsteam_api.so    (Goldberg shim - no real Steam)
  #   Dome Keeper/game/libgodotsteam.x86_64.so
  #   Dome Keeper/game/steam_settings/*
  installer = fetchIpfs {
    cid = "QmZgXGrnP6g9rjVJ1WXws7dcGCtH3yCNmDWY4FjoPDQ5cP";
    fallbackUrl = "https://archive.org/download/dome-keeper-linux-steam-rip-linuxrulez-phoenix-games-lab/Dome%20Keeper%20%28v.4.2.1%29%20%2B%20Pioneer%20Pack%20DLC%20%5BGodot%5D%20%5BGoldberg%5D%20%5BLinuxRuleZ%21%5D.sh";
    hash = "sha256-N3xEmH4KvHxTjTKEsbIDKMqZmA8VDZXKvK8hYJoRtJU=";
    name = "dome-keeper-linux.sh";
  };

  arcsz = 680326620;

  gameData = stdenv.mkDerivation {
    pname = "dome-keeper-data";
    version = "4.2.1";

    dontUnpack = true;

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      libGL
      alsa-lib
      libpulseaudio
      xorg.libX11
      xorg.libXi
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXext
      xorg.libXinerama
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      # Strip the YAD shell header off the front and decompress the xz
      # payload directly into the build dir. Skip everything except the
      # `Dome Keeper/game/` subtree -- the launcher script, desktop helper,
      # and uninstaller all assume a system YAD install and are useless
      # under our wrapper.
      tail -c ${toString arcsz} ${installer} | xzcat | tar -xf - --strip-components=2 "Dome Keeper/game"
      cp -r ./* "$out"/
      chmod +x "$out/domekeeper.x86_64"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dome-keeper";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  # Godot 4 binary; libsteam_api.so + libgodotsteam.x86_64.so dlopen by
  # bare name from the game dir's CWD. autoPatchelf rewrites the main
  # binary; the FHS env provides the libGL / libudev / libpulse the
  # engine reaches for at runtime.
  runtime = "custom";
  executable = "domekeeper.x86_64";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      mesa
      vulkan-loader
      alsa-lib
      libpulseaudio
      udev
      xorg.libX11
      xorg.libXi
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXext
      xorg.libXinerama
      xorg.libxcb
    ];

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

  # Mask /dev/input/event* from the bwrap sandbox. Godot 4.2.1's evdev
  # joypad scanner (platform/linuxbsd/joypad_linux.cpp::open_joypad)
  # accepts any device with EV_KEY + EV_ABS + ABS_X/ABS_Y as a gamepad
  # -- no ID_INPUT_TOUCHPAD filtering, no SDL involvement. A laptop
  # touchpad (PIXA i2c-hid here) advertises exactly those bits, so the
  # touchpad's absolute X position is read as the left-stick X axis:
  # the keeper "walks right" because ABS_X stays at its rightmost
  # value until the finger lifts, and menus navigate analog-stick
  # style for the same reason. Mouse + keyboard reach the game via the
  # gamescope wayland compositor (not /dev/input), so blanking the dir
  # is safe.
  #
  # bwrap.tmpfs alone is not enough: it lands at args-order ~172 in
  # lib/bwrap.nix, BEFORE --dev-bind /dev /dev at ~176, which then
  # overlays the entire /dev tree and wipes our tmpfs. mkAfter pushes
  # an extra --tmpfs onto the args list AFTER --dev-bind so the mask
  # actually wins.
  bwrap.args = lib.mkAfter [
    "--tmpfs"
    "/dev/input"
  ];

  meta = {
    description = "Dome Keeper (Bippinbits 2022, Pioneer Pack DLC, native Linux v4.2.1, Goldberg-emulated Steam)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dome-keeper";
  };
}
