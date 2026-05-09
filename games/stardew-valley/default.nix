{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  stdenv,
}:

let
  # GOG Linux release of Stardew Valley v1.6.15.24357 (build 78675).
  # Mojosetup .sh installer = shell-script header + zip archive, so unzip
  # handles it directly. The "Stardew Valley" ELF is a .NET 6.0 apphost
  # for a self-contained publish: libcoreclr.so / libhostfxr.so /
  # libclrjit.so live alongside in data/noarch/game/, plus bundled
  # libSDL2 / libFAudio / libopenal / libSkiaSharp / libGalaxy64 (GOG
  # Galaxy SDK). Layout: data/noarch/game/{Stardew Valley, *.dll, *.so,
  # Content/}, with rpath = $ORIGIN/netcoredeps on the apphost.
  installer = fetchIpfs {
    cid = "QmRkJfDH6RLK97dGbPGv7md9urEGkrUNoXCN63q43SVCyf";
    fallbackUrl = "https://archive.org/download/stardew-valley-linux-gog-phoenix-games-lab/stardew_valley_1_6_15_24357_8705766150_78675.sh";
    hash = "sha256-mq50ltEZKJ8WF9apw9dJ83zTLNE+NNMgAVq8LBtVcO8=";
    name = "stardew-valley-linux-gog-1.6.15.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "stardew-valley-data";
    version = "1.6.15.24357";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      libglvnd
      libxkbcommon
      libpulseaudio
      alsa-lib
      dbus
      fontconfig
      freetype
      openssl
      icu
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXi
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXxf86vm
    ];

    # libSDL2 / libFAudio / libopenal dlopen libudev/libGL/libwayland by
    # bare name at runtime — let those resolve via the FHS env, not the
    # autoPatchelf RPATH. liblttng-ust is the LTTng userspace tracer,
    # only loaded by libcoreclrtraceptprovider when DOTNET_EnableEventLog
    # is set; SDV doesn't enable tracing.
    autoPatchelfIgnoreMissingDeps = [
      "liblttng-ust.so.0"
      "libudev.so.1"
      "libwayland-client.so.0"
      "libwayland-egl.so.1"
      "libwayland-cursor.so.0"
    ];

    buildPhase = ''
      runHook preBuild
      # Mojosetup .sh has a 700KB shell-script header; unzip warns and
      # processes anyway. Tolerate the non-zero exit.
      unzip -q ${installer} 'data/noarch/game/*' || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r 'data/noarch/game/'* "$out"/
      # The apphost ELF has a space in its name. Rename it and replace
      # with a tiny launcher that scopes LD_LIBRARY_PATH so the bundled
      # libSDL2 / libcoreclr / libGalaxy64 win over anything the FHS
      # layer exposes (mirrors the carrion / loop-hero approach).
      mv "$out/Stardew Valley" "$out/StardewValley-bin"
      chmod +x "$out/StardewValley-bin"
      cat > "$out/StardewValley" <<'EOF'
      #!/bin/sh
      here="$(dirname "$0")"
      exec env LD_LIBRARY_PATH="$here:''${LD_LIBRARY_PATH:-}" "$here/StardewValley-bin" "$@"
      EOF
      chmod +x "$out/StardewValley"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "stardew-valley";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # Bundled libSDL2-2.0.so.0 dlopens libudev / libwayland / libGL by bare
  # name; libSkiaSharp dlopens fontconfig; the .NET OpenSsl native binding
  # dlopens libssl by SONAME. Use FHS env so /usr/lib resolves all three.
  runtime = "custom";
  executable = "StardewValley";

  targetPkgs =
    p: with p; [
      libGL
      libglvnd
      udev
      libxkbcommon
      libpulseaudio
      alsa-lib
      dbus
      fontconfig
      freetype
      openssl
      icu
      mesa
      vulkan-loader
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXi
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXxf86vm
      xorg.libxcb
      wayland
    ];

  env = {
    # Force X11 backend — bundled libSDL2 (2018-vintage) has flaky
    # Wayland support and gamescope nests Xwayland anyway.
    SDL_VIDEODRIVER = "x11";
    # .NET 6 GC server mode is overkill for SDV and inflates RSS.
    DOTNET_gcServer = "0";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Stardew Valley (native Linux, GOG v1.6.15.24357 build 78675)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "stardew-valley";
  };
}
