{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  patchelf,
  autoPatchelfHook,
  stdenv,
}:

let
  # Forager v2.0.0 (HopFrog, 2019) — the last native Linux release before
  # the developer dropped Linux support. The only public mirror is a
  # Russian-packaged repack by EshanGamespace: a zip wrapping a
  # makeself self-extractor (sfx.sh) whose payload is a FreeArc'Next
  # archive (archive.fa) containing the GameMaker Studio Linux binary
  # `Forager` plus its assets/ tree. The repack bundles its own
  # fa.x86_64 decoder, which we autoPatchelf and invoke at build time
  # to unpack the FreeArc payload (no equivalent decoder exists in
  # nixpkgs).
  installer = fetchIpfs {
    cid = "QmZJnJxJ1S8R8rwrXL9Vk9TQMqGhGccmGHXzNyhA5bKCQj";
    fallbackUrl = "https://archive.org/download/forager_linux_eshangamespace/forager_linux_eshangamespace.mfp";
    hash = "sha256-CPrLwDe9A2Sv4Zic+NbPTfxvMWNO1P8R/xA7I0ZXMRU=";
    name = "Forager_Linux.zip";
  };

  gameData = stdenv.mkDerivation {
    pname = "forager-data";
    version = "2.0.0";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      patchelf
      autoPatchelfHook
      pkgs.python3
    ];

    # The Forager GameMaker Studio binary NEEDs libstdc++/z/X11/GL/GLU/
    # Xext/Xrandr/Xxf86vm and links bundled libcrypto/libssl/libcurl-gnutls
    # (shipped in usr/lib/). autoPatchelf handles the system NEEDs from
    # buildInputs. The bundled libcurl-gnutls.so.4.5.0 was linked against
    # libnettle.so.6 (~2017) which is no longer in nixpkgs, so we replace
    # it with curlWithGnuTls's libcurl-gnutls.so.4 (currently 8.x, linked
    # against the modern libnettle.so.8). fa.x86_64 (FreeArc decoder, only
    # used at build time) just needs libstdc++/m/rt/pthread/gcc_s/c.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      libGL
      libGLU
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXxf86vm
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer}
      cd Forager_Linux
      # The makeself header runs `tail -c +N | gunzip` of itself plus
      # a checksum verification; --target writes the verified payload
      # to a directory, --noexec skips running the embedded installer
      # (yad-si.x86_64.sh) which would pop up a GUI dialog.
      sh ./sfx.sh --target sfx --noexec
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      # autoPatchelf the bundled FreeArc decoder so it can run under the
      # build sandbox's glibc, then have it extract the .fa payload.
      # `x` extracts, `-o+` overwrites, `-dp<dir>` sets the destination.
      chmod +x sfx/fa.x86_64
      autoPatchelf sfx/fa.x86_64
      mkdir -p "$TMPDIR/payload"
      sfx/fa.x86_64 x sfx/archive.fa -o+ "-dp$TMPDIR/payload"
      # The .fa archive nests everything under "Forager/"; flatten it so
      # the GameMaker binary lands at $out/Forager (path is the executable,
      # not a directory).
      mkdir -p "$out"
      cp -r "$TMPDIR/payload/Forager/." "$out/"
      chmod +x "$out/Forager"
      # The repack ships libsteam_api.so at the data root, but the
      # binary's rpath only searches usr/lib/ (via $ORIGIN). Without a
      # successful dlopen of libsteam_api.so the Steam-API glue never
      # null-checks the handle and segfaults on first call. Symlink it
      # into usr/lib/ so the bare-name dlopen resolves.
      ln -s ../../libsteam_api.so "$out/usr/lib/libsteam_api.so"

      # The bundled 2018-era libsteam_api.so binds against
      # __libc_dlopen_mode, a GLIBC_PRIVATE symbol that modern glibc
      # (2.34+) hides at link resolution. Build a tiny LD_PRELOAD shim
      # that forwards the call to plain dlopen() — that's the public
      # replacement glibc recommends — so the Steam SDK init proceeds
      # past its first dlopen without aborting.
      $CC -O2 -shared -fPIC ${./libc-dlopen-shim.c} \
        -ldl -o "$out/usr/lib/libc-dlopen-shim.so"
      # run.sh is the upstream launcher; restore read+exec perms (the
      # FreeArc archive stored it 0700 from the original packager).
      chmod 0755 "$out/run.sh"
      # Drop the bundled libcurl-gnutls.so.4.5.0 — it transitively NEEDs
      # libnettle.so.6 (nettle 3.4, ~2017) which is no longer packaged.
      # Replace it with curlWithGnuTls's libcurl-gnutls.so.4 (modern curl,
      # linked against libnettle.so.8). The binary uses libcurl only for
      # the leaderboard upload at game-end, so any API-level differences
      # don't block offline play.
      rm "$out/usr/lib/libcurl-gnutls.so.4.5.0"
      cp ${pkgs.curlWithGnuTls.out}/lib/libcurl-gnutls.so.4.*.* \
        "$out/usr/lib/libcurl-gnutls.so.4"
      chmod +w "$out/usr/lib/libcurl-gnutls.so.4"
      # The Forager binary imports curl_* symbols tagged CURL_GNUTLS_3
      # (the Debian gnutls-flavoured 7.x version-script tag). Modern
      # libcurl-gnutls exports them tagged CURL_GNUTLS_4. Clear the
      # per-symbol version requirement, then splice the now-orphaned
      # CURL_GNUTLS_3 entry out of .gnu.version_r — patchelf leaves the
      # Verneed shell behind and the loader refuses to bind without it.
      for sym in curl_easy_cleanup curl_easy_getinfo curl_easy_init \
                 curl_easy_setopt curl_global_cleanup curl_global_init \
                 curl_multi_add_handle curl_multi_cleanup curl_multi_init \
                 curl_multi_perform curl_multi_remove_handle \
                 curl_slist_append curl_slist_free_all; do
        patchelf --clear-symbol-version "$sym" "$out/Forager"
      done
      python3 ${./strip-verneed.py} "$out/Forager" CURL_GNUTLS_3
      # Tell the dynamic linker to look beside the binary for the bundled
      # libssl/libcrypto and our replacement libcurl in usr/lib/.
      patchelf --add-rpath "\$ORIGIN/usr/lib" "$out/Forager"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "forager";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "Forager";

  env = {
    # GameMaker Studio Linux runtime dlopens GL/X11/audio/SDL/openal by
    # bare name; provide the full set on LD_LIBRARY_PATH.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        libpulseaudio
        alsa-lib
        openal
        SDL2
        xorg.libX11
        xorg.libXext
        xorg.libXrandr
        xorg.libXxf86vm
        xorg.libxcb
      ]
    );
    # Preload the __libc_dlopen_mode shim so libsteam_api.so resolves
    # past its first dlopen() call against modern glibc (see build-
    # script comment for context).
    #
    # KNOWN ISSUE: with the shim Steam_Init succeeds (libsteam logs in
    # an anonymous user from ~/.steam) and the engine reaches "Entering
    # main loop", but then SIGFPEs on `idiv %edi` at Forager+0x1bcd10
    # — register state at crash shows edi/esi=0 (view width/height) and
    # rdx=0 (room display struct), and the globals at 0xa99db4/0xa99db8
    # have been clobbered from their 640x480 .data defaults to 0,0
    # somewhere between window creation and the first step. The
    # display_set_size(0,0) writer is at Forager+0x2f3fa0; its caller
    # at Forager+0x2f3ef0 propagates a (g_NewWindowWidth=0,
    # g_NewWindowHeight=0) pair. Replacing libsteam_api.so with a
    # Goldberg-style no-op stub avoided the FPE but the engine then
    # null-derefs SteamUser()->vtable, so a proper fix needs a stub
    # with real interface objects (multi-day effort). Parked: game
    # initialises cleanly up to first frame, then dies.
    LD_PRELOAD = "./usr/lib/libc-dlopen-shim.so";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Forager (native Linux, HopFrog v2.0.0 — last Linux build)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "forager";
  };
}
