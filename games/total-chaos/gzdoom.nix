# GZDoom g3.6.0 (2018) -- the exact engine Total Chaos standalone 1.00.0
# shipped with (gamedata/gzdoom.exe is "GZDoom g3.6.0", config written
# "by GZDoom g3.6.0 on Mon Dec 10 2018"). Modern GZDoom (4.x) mis-renders
# the mod's custom materials/postprocess shaders -- a new game spawns into
# a dark box of static noise. Pinning the period-correct 3.6.0 engine
# fixes the in-game rendering.
#
# 3.6.0 vendors its own bzip2/zlib/jpeg/gme, so the build is self-contained
# apart from SDL2/OpenAL/fluidsynth. The 2018 C++ does not compile cleanly
# with a modern gcc, so we relax a couple of error-as-warning categories.
{
  stdenv,
  fetchFromGitHub,
  cmake,
  makeWrapper,
  openal,
  fluidsynth,
  soundfont-fluid,
  libGL,
  SDL2,
  bzip2,
  zlib,
  libjpeg,
  libsndfile,
  mpg123,
  game-music-emu,
}:

stdenv.mkDerivation {
  pname = "gzdoom-totalchaos";
  version = "3.6.0";

  src = fetchFromGitHub {
    owner = "coelckers";
    repo = "gzdoom";
    rev = "g3.6.0";
    sha256 = "03yklhdppncaswy6l3fcvy8l8v1icfnm9f0jlszvibcm5ba7z0j1";
  };

  nativeBuildInputs = [
    cmake
    makeWrapper
  ];

  buildInputs = [
    SDL2
    libGL
    openal
    fluidsynth
    bzip2
    zlib
    libjpeg
    libsndfile
    mpg123
    game-music-emu
  ];

  enableParallelBuilding = true;

  # 2018 CMakeLists use cmake_minimum_required < 3.5, which modern CMake
  # refuses outright; this flag restores the old policy behaviour.
  cmakeFlags = [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];

  # 2018 sources predate stricter modern gcc diagnostics; downgrade the
  # ones promoted to hard errors so the old tree still compiles.
  # The build tools (lemon/re2c/zipdir) are K&R-era C that gcc 14+
  # rejects (implicit-int, missing prototypes) -- compile C as gnu89 and
  # relax those categories; -fpermissive handles the C++ side.
  env.NIX_CFLAGS_COMPILE = toString [
    "-Wno-error"
    "-fpermissive"
    "-Wno-narrowing"
    "-fcommon"
    "-Wno-implicit-int"
    "-Wno-implicit-function-declaration"
    "-Wno-int-conversion"
    "-Wno-incompatible-pointer-types"
  ];

  # Force the legacy C dialect for the K&R-style build tools.
  CFLAGS = "-std=gnu89";

  NIX_CFLAGS_LINK = [
    "-lopenal"
    "-lfluidsynth"
  ];

  preConfigure = ''
    sed -i \
      -e "s@/usr/share/sounds/sf2/@${soundfont-fluid}/share/soundfonts/@g" \
      -e "s@FluidR3_GM.sf2@FluidR3_GM2-2.sf2@g" \
      src/sound/mididevices/music_fluidsynth_mididevice.cpp
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 gzdoom "$out/lib/gzdoom/gzdoom"
    for i in *.pk3; do
      install -Dm644 "$i" "$out/lib/gzdoom/$i"
    done
    mkdir $out/bin
    makeWrapper $out/lib/gzdoom/gzdoom $out/bin/gzdoom
    runHook postInstall
  '';

  meta = {
    homepage = "https://github.com/coelckers/gzdoom";
    description = "GZDoom g3.6.0 -- period-correct engine for Total Chaos standalone 1.0";
    mainProgram = "gzdoom";
    platforms = [ "x86_64-linux" ];
  };
}
