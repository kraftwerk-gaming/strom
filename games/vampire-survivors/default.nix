{
  self,
  lib,
  pkgs,
  fetchIpfs,
  xz,
  gnutar,
  autoPatchelfHook,
  stdenv,
}:

let
  # Vampire Survivors 1.11.108 + 3 DLC ("Emergency Meeting"), Linux
  # native (Unity IL2CPP) build, packaged by LinuxRuleZ. The .sh is
  # a YAD/zstd-style self-extractor whose payload is actually an xz
  # tarball appended to the script; we slice off the last `arcsz`
  # bytes and decompress directly. The repack uses Goldberg (drop-in
  # libsteam_api.so) to satisfy Steamworks calls; no real Steam
  # process is required.
  installer = fetchIpfs {
    cid = "QmPv2Q9hiYUrERdUCft4XwW9XRWCZPKPqJZPKMaFkUodxL";
    fallbackUrl = "https://archive.org/download/vampire-survivors-linux-steam-rip-linuxrulez/Vampire%20Survivors%3A%20Emergency%20Meeting%20%28v.1.11.108%29%20%2B%203%20DLC%20%5BMULTi%5D%20%5BUnity3D%5D%20%5BGoldberg%5D%20%5BLinuxRuleZ%21%5D.sh";
    hash = "sha256-RhAPS1XIPAXpWQ1UtKlQliVR/eFwY4aESFHeGkdrr74=";
    name = "vampire-survivors-1.11.108-linux.sh";
  };

  # Size of the embedded xz tarball at the end of the .sh, copied from
  # the script's own `arcsz=...` declaration. Slicing with this exact
  # byte count avoids having to grep / parse the install script.
  archiveSize = 1150832316;

  gameData = stdenv.mkDerivation {
    pname = "vampire-survivors-data";
    version = "1.11.108";

    dontUnpack = true;

    nativeBuildInputs = [
      xz
      gnutar
      autoPatchelfHook
    ];

    # The Linux Unity stub VampireSurvivors NEEDs only libc/libm/libpthread
    # plus UnityPlayer.so (in-tree). UnityPlayer.so itself dlopens
    # GL/X11/audio/vulkan/wayland by bare name at runtime, supplied via
    # LD_LIBRARY_PATH below. libsteam_api.so (Goldberg) and the bundled
    # IL2CPP plugins all resolve from the same directory.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
    ];

    buildPhase = ''
      runHook preBuild
      tail -c ${toString archiveSize} ${installer} \
        | xz -d -c \
        | tar -xf -
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r "Vampire Survivors/game/." "$out"/
      chmod +x "$out/VampireSurvivors"
      # Drop the Windows redist files this Linux repack ships next to
      # the Linux build (UnityPlayer.dll / GameAssembly.dll / *.exe),
      # plus the 123/ "config defaults" snapshot mirror, which together
      # would otherwise more than double the closure size.
      rm -f "$out/UnityPlayer.dll" "$out/GameAssembly.dll" "$out/baselib.dll" \
        "$out/UnityCrashHandler64.exe"
      # The stock launcher.sh in this repack is broken (its single line
      # invokes ./VampireSurvivors.exe, which does not exist in the
      # Linux tree). We launch the Linux ELF directly from mkGame, so
      # drop the launcher to avoid confusion.
      rm -f "$out/launcher.sh"
      runHook postInstall
    '';

    # Bundled Unity / IL2CPP shared objects live next to the binary;
    # tell autoPatchelf to add $ORIGIN so the stub finds UnityPlayer.so
    # and the Plugins/* libraries find each other.
    appendRunpaths = [ "$ORIGIN" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "vampire-survivors";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "VampireSurvivors";
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        vulkan-loader
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        wayland
        udev
        libxkbcommon
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
      ]
    );
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Vampire Survivors + 3 DLC (Emergency Meeting v1.11.108, native Linux Unity / IL2CPP, Goldberg Steam shim)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "vampire-survivors";
  };
}
