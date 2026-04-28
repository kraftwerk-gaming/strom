{
  self,
  lib,
  pkgs,
  fetchIpfs,
  squashfsTools,
  autoPatchelfHook,
  stdenv,
  libGL,
  libpulseaudio,
  alsa-lib,
  libxkbcommon,
  wayland,
  libx11,
  libxext,
  libxcursor,
  libxrandr,
  libxi,
  vulkan-loader,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "balatro";
  runtime = "native";

  src = fetchIpfs {
    cid = "Qme9fvcZgvMBYbcSMo4poJr4P8Ykq8FaU2Hj5wXxkB1czt";
    hash = "sha256-snd/3n1fEGhjrQjhUzvgN/qnGKvp+bpzCiQaSepgP1M=";
    name = "balatro.squashfs";
  };

  nativeBuildInputs = [
    squashfsTools
    autoPatchelfHook
    stdenv.cc.cc.lib
    libGL
    libpulseaudio
    alsa-lib
    libxkbcommon
    wayland
    vulkan-loader
    libx11
    libxext
    libxcursor
    libxrandr
    libxi
  ];

  buildScript = ''
    dd if="$src" of=/tmp/balatro.squashfs bs=8192 skip=1
    unsquashfs -d /tmp/balatro /tmp/balatro.squashfs
    mkdir -p "$out"
    cp -r /tmp/balatro/. "$out"/
    chmod -R u+w "$out"
    autoPatchelf "$out"
  '';

  runScript = ''
    export LD_LIBRARY_PATH="$GAMEDIR/lib:${lib.makeLibraryPath [
      libGL
      libpulseaudio
      alsa-lib
      libxkbcommon
      wayland
      vulkan-loader
      libx11
      libxext
      libxcursor
      libxrandr
      libxi
    ]}:''${LD_LIBRARY_PATH:-}"
    exec "$GAMEDIR/bin/love" "$@"
  '';

  meta = {
    description = "Balatro (native Linux)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "balatro";
  };
}
