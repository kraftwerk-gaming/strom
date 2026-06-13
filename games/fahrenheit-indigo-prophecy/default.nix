{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gnutar,
  xz,
  patchelf,
  stdenv,
}:

let
  # Round 8 — source switch. Rounds 1-7 fought the 2005 Kelvin engine
  # (Atari retail + RELOADED NoCD crack) under wine/Proton. The post-
  # profile c0000005 NULL-write at Fahrenheit.exe+0xdfa06 reproduces on
  # every tried fix because the engine self-patches its own .text at
  # the crash offset during input-init (PlayOnLinux app-3776 documents
  # the same crash unfixed since 2018; static binary patches get
  # overwritten before the first mouse rawinput event fires). Wine,
  # Proton, dxvk frame caps, dinput8/xinput overrides, winebus
  # registry knobs, fps caps, BIK strip, and save quarantine all
  # tried in rounds 1-7 -- see git log fahrenheit-indigo-prophecy --
  # commits a252915..e842b5c for the failed-knob roster.
  #
  # Aspyr shipped a 2015 native Linux port as "Fahrenheit: Indigo
  # Prophecy Remastered" (Steam appid 312840) that sidesteps the
  # wine/proton/Kelvin-JIT issue entirely. This Steam-Rip carries the
  # same ELF + bundled libs Aspyr distributed via Steam, with
  # libsteam_api replaced by a Goldberg-style "ACTiVATED" stub so no
  # Steam runtime is needed. The ELF is a 32-bit Intel i386 binary
  # (interp /lib/ld-linux.so.2), so 32-bit host libs are required.
  # Source layout:
  #   game/Fahrenheit                  native i386 ELF
  #   game/lib{c++,iconv,ssl,...}.so   bundled C++/SSL runtime (i386)
  #   game/libMiles*.so                RAD Miles Sound System
  #   game/libsteam_api.so             Goldberg stub
  #   game/{binkawin,mss*}.asi/flt     Miles plugin loaders
  #   game/steamassets/bigfile_pc.*    multi-locale BIG data (~3.5 GB)
  #   game/resources/<lang>.lproj/     aslcore localized strings
  #   game/Saves/ACTiVATED/            seeded fresh-profile saves
  #   game/com.aspyr.fahrenheit.version.json   Aspyr build metadata
  installer = fetchIpfs {
    cid = "Qma75dt9uFe6vHUr81YPBX8gUTHXxCPo1qYqeB9g14NbuM";
    fallbackUrl = "https://archive.org/download/fahrenheit-indigo-prophecy-remastered-linux-steam-rip-activated/Fahrenheit_-_Indigo_Prophecy_Remastered_%28v%29_%5BLinux%2C_Steam-Rip%2C_ACTiVATED%5D.tar.xz";
    hash = "sha256-vrSLIwAnYQSRC94zZRfKOFT9PyJaLRNkibsFl2WEKCA=";
    name = "fahrenheit-indigo-prophecy-remastered-linux.tar.xz";
  };

  i686 = pkgs.pkgsi686Linux;

  gameData = stdenv.mkDerivation {
    pname = "fahrenheit-indigo-prophecy-data";
    version = "remastered-2015";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      xz
      patchelf
      pkgs.perl
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tar -xf ${installer} -C "$out"
      if [ -d "$out/game" ]; then
        cp -r "$out/game"/. "$out"/
        rm -rf "$out/game"
      fi
      chmod +x "$out/Fahrenheit"
      # 32-bit ELF -- repoint the interpreter at the NixOS i686 glibc.
      # The original RPATH is empty; the bundled libs live alongside
      # the binary so set RUNPATH=$ORIGIN, then LD_LIBRARY_PATH from
      # mkGame supplies the host-side i686 libs (GL/X11/audio/etc.).
      patchelf --set-interpreter "${i686.glibc}/lib/ld-linux.so.2" \
               --set-rpath '$ORIGIN' "$out/Fahrenheit"

      # Aspyr's shipped JSON (com.aspyr.fahrenheit.version.json plus
      # every resources/<lang>.lproj/aslcore.json) has trailing commas
      # before the closing brace, e.g.
      #     "DTZ_24" : "Dateline Daylight Time",
      #     }
      # The engine links its own classic JsonCpp Json::Reader, which is
      # strict and rejects trailing commas. An untouched copy launched
      # outside gamescope prints
      #     Failed to parse configuration
      #     * Line 373, Column 1
      #       Missing '}' or object member name
      # and the engine exits with a generic single-button "OK" error
      # dialog (round 8 symptom). Strip the offending trailing commas
      # so the strict parser accepts the files.
      find "$out" -name '*.json' -print0 \
        | xargs -0 -r -I{} perl -i -0777 -pe 's/,(\s*[}\]])/\1/g' {}
      runHook postInstall
    '';

    # The bundled libs are pre-patchelfed by Aspyr's build; autoPatchelf
    # would only confuse things (it skipped the 32-bit ELF on round 8's
    # first build attempt). Disable it and patchelf the main binary
    # manually above.
    dontStrip = true;
    dontPatchELF = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "fahrenheit-indigo-prophecy";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  # Native 32-bit Linux ELF. patchelf above set the i686 interpreter;
  # LD_LIBRARY_PATH below supplies the dlopen / DT_NEEDED targets the
  # binary expects: libGL/libX11/libasound/libopenal/libstdc++/libuuid
  # /libcrypto from the NixOS pkgsi686Linux set. The bundled
  # libMiles*/libsteam_api/libc++/libiconv/libcxxrt live next to the
  # ELF and resolve via the $ORIGIN RPATH set in patchelf.
  #
  # Round 11 -- ROOT CAUSE FOUND (the "unrecoverable error" dialog).
  # ----------------------------------------------------------------
  # Symptom (rounds 8-10): engine maps an X11 window, pops "An
  # unrecoverable error has occurred and Fahrenheit cannot continue."
  # (the kErrFatalErrorNotCaught key), the user clicks OK, the engine
  # exits. The engine emits zero bytes on stdout/stderr, so earlier
  # rounds could only guess. Round 10 hypothesised a libc++/libcxxrt
  # vs libstdc++ C++-ABI vtable clash throwing an uncaught exception.
  #
  # That hypothesis was WRONG. Traced under i686 gdb in the headless
  # gamescope sandbox:
  #   * `catch __cxa_throw` never fires -- there is NO C++ exception.
  #   * No SIGSEGV/SIGABRT/SIGBUS either -- it is not a crash.
  #   * The error dialog (XMapRaised) is reached on a clean call stack
  #     straight from main: the engine *deliberately* shows it.
  # Ghidra decompile of the init function (FUN_083f03dc) shows the
  # exact trigger:
  #     SDL_SetHint("SDL_VIDEO_X11_XRANDR", ...)
  #     SDL_SetHint("SDL_VIDEO_X11_XINERAMA", ...)
  #     SDL_SetHint("SDL_MOUSE_RELATIVE_MODE_WARP", ...)
  #     if (SDL_Init(0x7021) < 0)            // TIMER|VIDEO|JOYSTICK|
  #         <show kErrFatalErrorNotCaught>   // GAMECONTROLLER|HAPTIC|EVENTS
  # Breaking right after the SDL_Init call and reading the SDL error
  # buffer gives the smoking gun:
  #     SDL_Init(0x7021) -> -1
  #     SDL error: "Could not initialize UDEV"
  # The statically-linked SDL2 dlopen()s libudev.so.1 (then .so.0; see
  # SDL2 src/core/linux/SDL_udev.c) to enumerate joystick/gamecontroller
  # /haptic devices. Neither soname was on the i686 library path, so
  # SDL_UDEV_Init() failed and SDL_Init returned -1 for the whole
  # process -- hence the generic fatal dialog. /run/udev IS bind-mounted
  # into the sandbox; the only thing missing was the i686 libudev.so.1
  # to dlopen, which the LD_LIBRARY_PATH addition below now supplies.
  #
  # (The C++-ABI clash from round 10 is genuine -- the binary links
  # libstdc++ AND libc++/libcxxrt, whose cxxabi RTTI vtables differ in
  # size, e.g. _ZTVN10__cxxabiv120__si_class_type_infoE is 36 bytes in
  # libcxxrt vs 44 in nix's libstdc++. We keep the documented Aspyr
  # community LD_PRELOAD mitigation below so the first real gameplay
  # exception doesn't blow up -- but it was never what blocked boot.)
  runtime = "native";
  executable = "Fahrenheit";

  env = {
    SteamAppId = "312840";
    SteamGameId = "312840";
    # Round 11: force the bundled libcxxrt to load before nix's
    # libstdc++ so the C++ ABI symbols (_ZTVN10__cxxabiv1...E vtables
    # and __cxa_throw) resolve to the bundled runtime the Aspyr binary
    # was built against.
    #
    # Why this matters (verified with readelf on the bundled libs):
    #   * The ELF lists BOTH libstdc++.so.6 (DT_NEEDED, ahead of the
    #     C++ libs) and libc++.so.1 + libcxxrt.so.
    #   * libcxxrt.so DEFINES the cxxabi typeinfo vtables and
    #     __cxa_throw as plain GLOBAL symbols (unversioned).
    #   * libc++.so.1 imports those same symbols UNDEFINED -- it was
    #     built to bind them against libcxxrt.
    #   * nix's i686 libstdc++.so.6 ALSO defines them, but as
    #     WEAK @@CXXABI_1.3 versioned symbols. Because libstdc++ loads
    #     first, the loader binds libc++'s exception machinery to
    #     libstdc++'s vtables instead of libcxxrt's. The two ABIs'
    #     type_info objects then don't compare equal, so a thrown C++
    #     exception fails to match its catch handler, unwinds to the
    #     engine's top-level guard, and triggers the localized
    #     kErrFatalErrorNotCaught dialog at boot.
    #
    # The community fix (shared verbatim across Aspyr's sibling ports
    # Borderlands 2 and Civilization VI, which ship the identical
    # libc++/libcxxrt pair and throw the same "An unrecoverable error
    # has occurred" message) is the Steam launch option
    #     LD_PRELOAD='./libcxxrt.so:/usr/$LIB/libstdc++.so.6'
    # i.e. force the bundled libcxxrt to the FRONT of the global search
    # scope so its unversioned cxxabi definitions win, then let
    # libstdc++ load second for the rest of the GNU C++ runtime the
    # binary's DT_NEEDED still pulls. (NOT libc++.so.1 in the preload --
    # libc++ loads via DT_NEEDED and binds its UND cxxabi symbols to the
    # now-first libcxxrt.)
    #
    # BARE names do NOT work: ld.so resolves LD_PRELOAD entries against
    # the standard search path BEFORE the binary's $ORIGIN/RUNPATH, so
    # "libcxxrt.so:libc++.so.1" produced 42x "cannot be preloaded ...
    # ignored" and silently did nothing for ~10 rounds. We use absolute
    # paths instead. The game tree is overlay-mounted at the fixed
    # sandbox path /tmp/.strom-overlay (STROM_OVERLAY in mk-game.nix)
    # and the inner script cd's there before exec, so libcxxrt.so lives
    # at /tmp/.strom-overlay/libcxxrt.so. The i686 libstdc++ is the same
    # one already on LD_LIBRARY_PATH below.
    #
    # Both preload entries are 32-bit. The outer gamescope/Xwayland
    # chain is x86_64 and inherits this env, so ld.so prints a harmless
    # "wrong ELF class: ELFCLASS32: ignored" per entry there and carries
    # on (a window still maps); only the i686 Fahrenheit process honours
    # the preload.
    LD_PRELOAD = "/tmp/.strom-overlay/libcxxrt.so:${i686.gcc-unwrapped.lib}/lib/libstdc++.so.6";
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with i686;
      [
        libGL
        libGLU
        libglvnd
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libXxf86vm
        xorg.libxcb
        alsa-lib
        openal
        libpulseaudio
        # libudev.so.1 -- the statically-linked SDL2 dlopen()s this to
        # enumerate joystick/gamecontroller/haptic devices. Without it
        # SDL_UDEV_Init() fails, SDL_Init(0x7021) returns -1, and the
        # engine aborts boot with the kErrFatalErrorNotCaught dialog.
        # This is THE fix that gets the game past the startup error.
        systemdLibs
        # openssl 1.0 is EOL; the binary's DT_NEEDED libcrypto.so.1.0.0
        # and libssl.so.1.0.0 are *bundled* and resolve via $ORIGIN, so
        # we don't need a host-side openssl 1.0 here. Same for libuuid
        # (libuuid.so.1.3.0 is bundled).
        gcc-unwrapped.lib
        stdenv.cc.cc
        zlib
        libuuid
      ]
    );
  };

  # The Aspyr build writes saves under the game directory (game/Saves/
  # <profile>/*.idx + *.dat). Persist that subtree so it survives
  # store-path rebuilds and overlay wipes.
  saveLocations = [ "Saves" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Fahrenheit: Indigo Prophecy Remastered (Aspyr 2015 native Linux i686 port, Goldberg Steam shim)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "fahrenheit-indigo-prophecy";
  };
}
