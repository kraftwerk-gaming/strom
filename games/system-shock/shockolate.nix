{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  SDL2,
  SDL2_mixer,
  fluidsynth,
  alsa-lib,
  libGL,
}:

# Shockolate is a native SDL2 source port of System Shock (Looking Glass
# 1994), based on the PowerPC source code Night Dive released in 2018.
# Pinned to the GCC 14 fix merge (Oct 2025); the last tagged release
# (v0.8.2) predates that fix and won't build against current glibc
# headers. CMake defaults `ENABLE_*` to BUNDLED, which expects build_ext
# trees populated by `build_deps.sh` (curl-fetched SDL2 2.0.9 etc.);
# override every option to `ON` so the build links against nixpkgs'
# system libraries. The repo has no `install` target — the produced
# binary expects `res/` and `shaders/` siblings at the CWD — so we copy
# the shaders alongside the binary and let the game derivation arrange
# `res/` in the per-game overlay.
stdenv.mkDerivation {
  pname = "shockolate";
  version = "0-unstable-2025-10-01";

  src = fetchFromGitHub {
    owner = "Interrupt";
    repo = "systemshock";
    rev = "4cc3d07dfff2d11b6d3a0a9960a51cf4ca253690";
    hash = "sha256-pXxpzrpEdk1zUlRHNg8imVU5WUJ3mVHcYBswdKkAhUs=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    SDL2
    SDL2_mixer
    fluidsynth
    alsa-lib
    libGL
  ];

  cmakeFlags = [
    # Upstream still declares `cmake_minimum_required(VERSION 3.1)`,
    # which modern CMake rejects outright; we don't touch the build
    # otherwise, so opt into the legacy policy via the documented
    # compatibility flag.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DENABLE_SDL2=ON"
    "-DENABLE_SOUND=ON"
    "-DENABLE_FLUIDSYNTH=ON"
    "-DENABLE_OPENGL=ON"
  ];

  # The default target `make` builds the example test executables
  # (`StarTest`, `BitmapTest`, `FixTest`) alongside `systemshock`; the
  # tests link partial libs and aren't useful at runtime. Build only the
  # game target.
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES systemshock
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 systemshock $out/bin/systemshock
    mkdir -p $out/share
    cp -r $src/shaders $out/share/shockolate-shaders
    runHook postInstall
  '';

  passthru = {
    # Path to the shaders tree that game derivations need to drop next
    # to the runtime CWD (Shockolate hard-codes `shaders/<name>` paths
    # via fopen relative to CWD on non-Apple platforms).
    shaders = "share/shockolate-shaders";
  };

  meta = {
    description = "Shockolate, a cross-platform SDL2 source port of System Shock (1994)";
    homepage = "https://github.com/Interrupt/systemshock";
    license = lib.licenses.gpl3Only;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "systemshock";
  };
}
