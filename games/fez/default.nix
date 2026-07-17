{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  patchelf,
  zlib,
  stdenv,
  libGL,
  libX11,
  libXext,
  libXcursor,
  libXi,
  libXrandr,
  libXfixes,
  libXrender,
  libxcb,
  libpulseaudio,
  alsa-lib,
  libxkbcommon,
  systemdLibs,
}:

let
  # GOG Linux installer (Makeself + mojosetup) for FEZ, version 2.1.0.4.
  installer = fetchIpfs {
    cid = "QmWbKaPKumQeNjRKEzxA1gSceAjATiFQyznPz4Ne4JRVHH";
    fallbackUrl = "https://archive.org/download/fez-linux-gog-phoenix-games-lab/gog_fez_2.1.0.4.sh";
    hash = "sha256-tKpIMX894t2K9Oas4XUbHEFQu07GfL6aRAXqix15/UU=";
    name = "gog_fez_2.1.0.4.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "fez-data";
    version = "2.1.0.4";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      patchelf
    ];

    buildPhase = ''
      runHook preBuild
      # The GOG installer is a Makeself archive containing a gzip header and
      # a zip payload. unzip finds the zip automatically, skipping the preamble.
      # unzip exits 1 on the extra-bytes warning even when extraction succeeds.
      unzip -q ${installer} "data/noarch/game/*" || [ $? -eq 1 ]
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/FEZ.bin.x86_64" "$out/FEZ.bin.x86"

      # Bundled libs in lib64/ need $ORIGIN in rpath so they find each other
      # (libvorbisfile -> libvorbis -> libogg). The main binary already has
      # $ORIGIN/lib64 rpath. libMonoPosixHelper.so needs libz.so.1 from zlib.
      for lib in "$out"/lib64/*.so*; do
        patchelf --set-rpath "\$ORIGIN:${
          lib.makeLibraryPath [
            zlib
            stdenv.cc.cc.lib
          ]
        }" "$lib"
      done

      # Patch the interpreter of the main binary so it finds ld-linux on NixOS.
      patchelf --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" "$out/FEZ.bin.x86_64"

      # MonoKickstart DllImport searches libs relative to the exe directory
      # (not lib64/), so symlink bundled libs into the game root.
      for lib in "$out"/lib64/*.so*; do
        ln -sf "lib64/$(basename "$lib")" "$out/$(basename "$lib")"
      done

      runHook postInstall
    '';

    dontStrip = true;
    dontMoveLib64 = true;
    dontPatchELF = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "fez";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "FEZ.bin.x86_64";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1280;
    nested-height = 720;
    flags."--expose-wayland" = true;
  };

  env = {
    SDL_VIDEODRIVER = "x11";

    # FEZ bundles an ancient SDL2 (pre-2.0.9: no HIDAPI, hg-revision
    # build) that dlopens libudev.so.1 to enumerate input devices. The
    # libs below don't include udev, and MonoKickstart prepends the game
    # dir to LD_LIBRARY_PATH, so without systemdLibs here SDL's udev load
    # fails, its classic /dev/input fallback finds nothing, and the pad is
    # invisible (SDL_NumJoysticks == 0). systemdLibs supplies
    # libudev.so.1; /run/udev is already bound into the sandbox
    # (lib/mk-game.nix), so auto-enumeration then works across reconnects
    # without hardcoding a dynamic /dev/input/eventN.
    LD_LIBRARY_PATH = lib.makeLibraryPath [
      libGL
      libX11
      libXext
      libXcursor
      libXi
      libXrandr
      libXfixes
      libXrender
      libxcb
      libpulseaudio
      alsa-lib
      libxkbcommon
      systemdLibs
    ];

    # Even once enumerated, the bundled controller DB has no entry for the
    # xpadneo Bluetooth Xbox pad (evdev id 045e:028e, bus 0005, ver 1130
    # -> the old-SDL GUID below, computed without the crc16 that SDL
    # >=2.0.12 adds), so FNA's GamePad API sees an unmapped joystick and
    # reports no controller. Inject the mapping (verified against the
    # game's own SDL: SDL_IsGameController -> 1). Layout is the standard
    # Xbox 360 pad that xpadneo emulates by default.
    SDL_GAMECONTROLLERCONFIG = "050000005e0400008e02000030110000,Xbox 360 Controller,a:b0,b:b1,x:b2,y:b3,back:b6,guide:b8,start:b7,leftstick:b9,rightstick:b10,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5,platform:Linux,";
  };

  meta = {
    description = "FEZ (native Linux, GOG)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "fez";
  };
}
