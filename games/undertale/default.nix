{
  self,
  lib,
  pkgs,
  fetchIpfs,
  autoPatchelfHook,
  pkgsi686Linux,
}:

let
  # Phoenix Games Lab Linux GOG repack of Undertale (v1.08). The .tar.xz
  # is a flat `game/` tree containing the precompiled `runner` binary
  # plus the data and assets directories. The "Fixed Libs" tag means
  # the repack bundles libssl.so.1.0.0 / libcrypto.so.1.0.0 in
  # `game/lib32/`; everything else (libGL, libX11, libopenal, libstdc++,
  # …) must come from the host.
  src = fetchIpfs {
    cid = "QmU97VATpxu6sC7KGNBw8sAqiABQTQ6UW8kj7Y6AiGQPH3";
    fallbackUrl = "https://archive.org/download/undertale-linux-gog-phoenix-games-lab/game-Undertale_%28v1.08%29_%5BLinux%2C_GOG%2C_Archive%2C_Fixed_Libs%5D.tar.xz";
    hash = "sha256-uQVUyDDlfAtXwGdLcQoLU2CGgabI0tOzS8xIGEmMR1M=";
    name = "undertale-linux-gog.tar.xz";
  };

  # `game/runner` is a 32-bit i386 ELF (interpreter /lib/ld-linux.so.2,
  # no RPATH). Build under pkgsi686Linux so autoPatchelf picks the i686
  # ld-linux as its interpreter target; that lets it patch a 32-bit
  # ELF on a 64-bit host (same pattern as cave-story--1).
  gameData = pkgsi686Linux.stdenv.mkDerivation {
    pname = "undertale-data";
    version = "1.08";

    inherit src;
    # The .tar.xz unpacks several top-level entries (.mojosetup, docs,
    # game, support, start.sh, ...). Stop stdenv from cd'ing into a
    # single source root.
    sourceRoot = ".";

    nativeBuildInputs = [
      autoPatchelfHook
    ];

    # NEEDED entries on runner: libstdc++, libz, libXxf86vm, libGL,
    # libopenal, libm/rt/pthread/dl/c (libc), libcrypto.so.1.0.0,
    # libssl.so.1.0.0, libXext, libX11, libXrandr, libGLU, libgcc_s.
    # libssl/libcrypto are satisfied by the bundled lib32/ copies
    # via appendRunpaths below; the rest come from pkgsi686Linux.
    buildInputs = with pkgsi686Linux; [
      stdenv.cc.cc.lib
      zlib
      libGL
      libGLU
      libglvnd
      openal
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXxf86vm
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r ./. "$out"/
      chmod +x "$out/game/runner"
      runHook postInstall
    '';

    # The runner has no RPATH and the bundled libssl.so.1.0.0 /
    # libcrypto.so.1.0.0 live in game/lib32/ next to it. Tell
    # autoPatchelf to add `$ORIGIN/lib32` to runner's RUNPATH so it
    # finds the bundled OpenSSL 1.0 pair without an env override.
    appendRunpaths = [ "$ORIGIN/lib32" ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "undertale";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "game/runner";

  meta = {
    description = "Undertale (2015 Toby Fox, Linux GOG repack via Phoenix Games Lab)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "undertale";
  };
}
