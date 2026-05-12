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
  # GOG Linux release of Loop Hero (1.1054 / build 55873). The mojosetup
  # .sh installer is a shell-script header followed by a zip archive, so
  # unzip handles it directly. Layout: data/noarch/game/Loop_Hero (ELF),
  # run.sh, libsteam_api.so, assets/, plus assets/linuxlibs/ (bundled
  # libcurl/libopenal/libssl 1.1/librtmp).
  installer = fetchIpfs {
    cid = "QmeC5wZown2ZhNusa8dEq342Siqk88RxrJFBgxwQuVPTwD";
    fallbackUrl = "https://archive.org/download/loop-hero-linux-gog-phoenix-games-lab/Game%2Floop_hero_1_1054_55873.sh";
    hash = "sha256-qItSj+ADA8ehsp96GZmdYIgKvof+Kz/JQteG0NAGSV8=";
    name = "loop-hero-linux-gog-1.1054.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "loop-hero-data";
    version = "1.1054";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      libGLU
      libxkbcommon
      libpulseaudio
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXxf86vm
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      openssl
      openal
    ];

    # The bundled libcurl/libopenal/libssl 1.1/librtmp need autoPatchelf
    # to find their dependencies, but skip the binary so autoPatchelf
    # doesn't strip its bundled-lib RPATH; we set it manually below.
    # Bundled libcurl/librtmp pull in a long list of legacy SSL/krb5/ldap/
    # nettle/idn libs that nixpkgs no longer carries. The game runs inside
    # the FHS env at runtime, so resolve everything at runtime via
    # LD_LIBRARY_PATH and just suppress autoPatchelf's complaints.
    autoPatchelfIgnoreMissingDeps = [
      "libssl.so.1.1"
      "libcrypto.so.1.1"
      "librtmp.so.1"
      "libpsl.so.5"
      "libgssapi_krb5.so.2"
      "libldap_r-2.4.so.2"
      "liblber-2.4.so.2"
      "libz.so.1"
      "libgnutls.so.30"
      "libhogweed.so.6"
      "libnettle.so.8"
      "libgmp.so.10"
      "libnghttp2.so.14"
      "libidn2.so.0"
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/Loop_Hero"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "loop-hero";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # The bundled libssl 1.1 / libcrypto 1.1 in assets/linuxlibs/ are
  # ancient and dlopen'd at runtime by libcurl. Use the FHS env so the
  # game's LD_LIBRARY_PATH=./assets/linuxlibs/ in run.sh resolves
  # correctly while still picking up libGL / libX11 / libopenal from
  # the system tree.
  runtime = "custom";
  executable = "Loop_Hero";

  targetPkgs =
    p: with p; [
      libGL
      libGLU
      libglvnd
      libxkbcommon
      libpulseaudio
      alsa-lib
      dbus
      mesa
      vulkan-loader
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXxf86vm
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      xorg.libxcb
    ];

  env = {
    # run.sh prepends ./assets/linuxlibs/ so the bundled libssl 1.1 +
    # libcurl + libopenal win over anything the FHS layer exposes.
    LD_LIBRARY_PATH = "assets/linuxlibs";
  };

  # The GameMaker Linux Runner ("YoYo Games Linux Runner V1.3")
  # enumerates every /dev/input/event* node as a joystick. On a
  # laptop that includes the touchpad: its absolute X/Y axes get
  # interpreted as analog stick input (range 0..1337 mapped into
  # signed 16-bit), so the game's UI cursor is pulled to a corner
  # and menu clicks land on the wrong button. The runner ignores
  # -nodirectinput, so mask /dev/input entirely. Mouse + keyboard
  # still work via Xwayland; controller users can use Steam Input
  # or unset this. Same workaround as anno-1503/anno-1602-ad.
  bwrap.tmpfs = [ "/dev/input" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      # The GameMaker runner uses XGrabPointer / raw X11 input. Under
      # gamescope's nested Xwayland, pointer events are only delivered
      # to the focused surface; force-grab-cursor keeps the cursor and
      # button events locked to the game window so menu clicks land.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Loop Hero (native Linux, GOG v1.1054 build 55873)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "loop-hero";
  };
}
