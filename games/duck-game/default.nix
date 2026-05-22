{
  self,
  lib,
  pkgs,
  fetchIpfs,
  file,
  unzip,
}:

# Duck Game (Landon Podbielski / Adult Swim Games, 2014/2017) packaged
# from DuckGameRebuilt — a community decompilation/rebuild that ships
# DuckGame.exe as a Mono-runnable .NET 4.8 assembly alongside an FNA
# port. The upstream release is native-on-Linux: bundled
# libFNA3D.so.0 / libFAudio.so.0 / libtheorafile.so plus a real
# Steamworks libsteam_api.so. SteamAPI_Init returns false at runtime
# (we're not under a Steam client) but Duck Game treats that as a soft
# error — the game logs "Steam INIT Failed!" and continues.
#
# Upstream zip also ships a libSDL2-2.0.so.0, but the file in v1.4.7
# is 32-bit (a packaging mistake by upstream). Mono on x86_64 fails to
# dlopen it, FNAPlatform's static ctor throws DllNotFoundException,
# and the game dies before reaching the main loop. Fix: drop the
# bundled libSDL2-2.0.so.0 in buildScript and rely on FHS-supplied
# nixpkgs SDL2 (added to targetPkgs below) — FNA's dllmap targets the
# bare soname so the FHS /usr/lib copy is found via the standard
# linker search path.
#
# Runtime is `custom` so the launch passes through an FHS-user-env
# chroot. FNA's dllmap (FNA.dll.config) targets bare sonames like
# `libSDL2-2.0.so.0`, and the bundled .so files want libudev /
# libwayland / libGL / libpulse / etc by bare name; the FHS layer
# supplies them via /usr/lib while LD_LIBRARY_PATH=$here scopes the
# bundled libs above the FHS copies. Mono is provided via targetPkgs
# so it lives inside the FHS chroot together with its System.* DLLs.

let
  src = fetchIpfs {
    cid = "Qmet6FqCu7FUP8PP1JfkP6MHp9QXm2TGhTbGzw5FE6i1pM";
    fallbackUrl = "https://github.com/TheFlyingFoool/DuckGameRebuilt/releases/download/v1.4.7/DuckGameRebuilt.zip";
    hash = "sha256-3J2U6FwHM8aU8zU9SWFn4kwMg0khEiEMprtxEIRitsU=";
    name = "duck-game.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "duck-game";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    file
    unzip
  ];

  # DuckGameRebuilt.zip extracts to a flat layout (DuckGame.exe + Content/
  # + bundled .so siblings + DuckGame.sh launcher). Drop the bundled
  # launcher and outputlog.txt-style tee — strom's preRun handles logs
  # and the wrapper invokes our own DuckGame shell launcher instead.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
    chmod -R u+w "$out"
    # Drop the bundled launcher: our own wrapper below sets
    # LD_LIBRARY_PATH and invokes mono explicitly. Keep the dead-code
    # OSX-Linux-x64/libsteam_api.so duplicate too — community stub, only
    # ~400KB, simplest to leave in place.
    rm -f "$out/DuckGame.sh"

    # Drop the bundled libSDL2-2.0.so.0: upstream v1.4.7 ships the i386
    # build of SDL2, which 64-bit Mono can't dlopen. FNA's dllmap will
    # fall through to the FHS-supplied SDL2 (added to targetPkgs).
    case "$(file -b "$out/libSDL2-2.0.so.0" 2>/dev/null || true)" in
      *"ELF 32-bit"*) rm -f "$out/libSDL2-2.0.so.0" ;;
    esac

    # Drop a tiny launcher next to the assembly so the wrapper can call
    # a single executable. LD_LIBRARY_PATH prefix puts the bundled
    # libSDL2 / libFNA3D / libFAudio / libtheorafile / libsteam_api on
    # the dlopen search path ahead of the FHS /usr/lib copies — FNA's
    # dllmap targets these exact sonames and the community Steam stub
    # is the version we want loaded.
    #
    # Name the launcher DuckGame.sh (matching upstream's bundled name)
    # rather than bare DuckGame, because the game itself creates a
    # DuckGame/ save directory under $HOME (= $STROM_GAMEDIR, the
    # overlay upper). With the launcher named DuckGame, the upper-
    # layer save dir shadows the lower-layer launcher file →
    # gamescope exec returns EACCES on what's now a directory.
    cat > "$out/DuckGame.sh" <<'EOF'
    #!/bin/sh
    here="$(dirname "$0")"
    cd "$here"
    export LD_LIBRARY_PATH="$here:''${LD_LIBRARY_PATH:-}"
    exec mono ./DuckGame.exe "$@"
    EOF
    chmod +x "$out/DuckGame.sh"
  '';

  runtime = "custom";
  executable = "DuckGame.sh";

  # FHS chroot. Mono lives here so the launcher's bare `mono` resolves
  # to a managed runtime whose System.* DLLs are co-located. Bundled
  # libSDL2 / FNA3D / FAudio dlopen GL / wayland / udev / pulse / X11
  # by bare soname, so the standard graphics+audio FHS set covers them.
  targetPkgs =
    p: with p; [
      mono
      # Upstream v1.4.7 ships a 32-bit libSDL2; buildScript drops it
      # and FNA's dllmap falls through to this 64-bit FHS-supplied copy.
      SDL2
      libGL
      libglvnd
      udev
      libxkbcommon
      libpulseaudio
      alsa-lib
      dbus
      mesa
      vulkan-loader
      wayland
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXxf86vm
      xorg.libxcb
    ];

  env = {
    # Bundled libSDL2 is the 2.x release FNA ships with; force X11 so
    # gamescope's Xwayland nest is the rendering target rather than a
    # half-supported Wayland path.
    SDL_VIDEODRIVER = "x11";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Duck Game (DuckGameRebuilt v1.4.7, native Linux via Mono + FNA)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "duck-game";
  };
}
