{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  stdenv,
  libGL,
  libGLU,
  libX11,
  freetype,
  libvorbis,
  openal,
}:

let
  # Hemisphere Games' DRM-free Linux release of Osmos (Humble Indie
  # Bundle 2 era). Tarball contains 32-bit and 64-bit native ELF
  # binaries (Osmos.bin32, Osmos.bin64) plus shared assets.
  src = fetchIpfs {
    cid = "QmTxVZRtd8bs8bdtfBciFS1pKhXxKY8KY9jKrL5rxPNxb6";
    fallbackUrl = "";
    hash = "sha256-+Km/Vdwi7jL+7sVjMFjCjRgRowVPbr7T+fMlHFF50gI=";
    name = "Osmos_1.6.1.tar.gz";
  };

  gameData = stdenv.mkDerivation {
    pname = "osmos-data";
    version = "1.6.1";

    inherit src;

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    buildInputs = [
      stdenv.cc.cc.lib
      libGL
      libGLU
      libX11
      freetype
      libvorbis
      openal
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r . "$out"/
      # AUR osmos.install: defaultsoundDevice prefix '"-' silences audio
      # on PulseAudio/PipeWire setups; strip the leading dash so OpenAL
      # picks the system default.
      if [ -f "$out/defaults.cfg" ]; then
        sed -ri 's/^(soundDevice ")-/\1/' "$out/defaults.cfg"
      fi
      chmod +x "$out/Osmos.bin32" "$out/Osmos.bin64"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "osmos";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "Osmos.bin64";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Osmos (native Linux, Hemisphere Games)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "osmos";
  };
}
