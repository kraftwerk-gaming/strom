{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  SDL2,
  curl,
  openal,
}:

# Prebuilt linux-amd64 binary drop of OpenMoHAA v0.82.1 (openmoh/openmohaa,
# Aug 2025). OpenMoHAA is an open re-implementation of the original 2002
# Medal of Honor: Allied Assault engine (Quake3-derived, ioquake3-based)
# that loads the retail game's pak0..pak5.pk3 + sound/ + video/ directly,
# bypassing the SafeDisc 2 wrapper that ships in the retail MOHAA.exe.
# Building from source would pull in CMake + a long submodule chain
# (libmad, mss32 stubs, ...); the upstream Linux release tarball already
# bundles `game.so` and `cgame.so` (the per-game native modules) plus
# libSDL2/libcurl/libopenal so the only thing autoPatchelf needs to fix
# is the dynamic interpreter and the bare libc/libstdc++ NEEDEDs.
stdenv.mkDerivation {
  pname = "openmohaa";
  version = "0.82.1";

  src = fetchurl {
    url = "https://github.com/openmoh/openmohaa/releases/download/v0.82.1/openmohaa-v0.82.1-linux-amd64.zip";
    hash = "sha256-V2ktBXpoSvt/fpGmH82MBispqxtjnydFODAISojNZTw=";
  };

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
  ];

  # autoPatchelf only needs the host-side runtime stack (libc, libstdc++,
  # libgcc, libm); SDL2/libcurl/libopenal ship inside the release zip and
  # land next to the binary in $out/share/openmohaa, where the engine
  # picks them up via the $ORIGIN rpath set below.
  buildInputs = [
    stdenv.cc.cc
    SDL2
    curl
    openal
  ];

  dontUnpack = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/openmohaa"
    unzip -q "$src" -d "$out/share/openmohaa"
    chmod +x "$out/share/openmohaa"/{openmohaa,omohaaded,launch_openmohaa_*}

    # Drop the bundled libSDL2 / libcurl / libopenal: SDL2 in particular
    # carries no rpath to its host-side video drivers, so when started
    # from a Nix store path it falls back to SDL_VIDEODRIVER=offscreen
    # and the engine bails with "could not load OpenGL subsystem". Letting
    # autoPatchelf resolve libSDL2-2.0.so.0 / libcurl.so.4 / libopenal.so.1
    # against nixpkgs picks up the proper Wayland/X11/GLVND-aware builds.
    rm -f "$out/share/openmohaa/libSDL2-2.0.so.0" \
          "$out/share/openmohaa/libcurl.so.4" \
          "$out/share/openmohaa/libopenal.so.1"

    # game.so / cgame.so / openmohaa live in the same dir; setting rpath
    # to $ORIGIN keeps the inter-binary dlopen-by-basename chain (the
    # engine dlopens "./cgame.so" and "./game.so" relative to fs_basepath,
    # but also walks LD_LIBRARY_PATH and rpath for the .so siblings).
    for f in openmohaa omohaaded launch_openmohaa_base \
             launch_openmohaa_spearhead launch_openmohaa_breakthrough \
             game.so cgame.so; do
      patchelf --set-rpath '$ORIGIN' "$out/share/openmohaa/$f"
    done

    mkdir -p "$out/bin"
    ln -s "$out/share/openmohaa/openmohaa" "$out/bin/openmohaa"

    runHook postInstall
  '';

  meta = {
    description = "OpenMoHAA, native source port of Medal of Honor: Allied Assault (prebuilt linux-amd64 release)";
    homepage = "https://www.openmohaa.org/";
    license = lib.licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "openmohaa";
  };
}
