{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  python3,
  stdenv,
}:

let
  # GOG Linux release of Encased: A Sci-Fi Post-Apocalyptic RPG
  # (Dark Crystal Games 2021), v1.3.1517.1645 build 55620. GOG ships a
  # Makeself 2.2.0 / mojosetup self-extracting installer: a ~900KB
  # makeself shell+mojo engine header with the real game payload
  # appended as a plain zip (game tree at data/noarch/game/), so `unzip`
  # pulls it straight out -- it warns about the leading "extra bytes"
  # and exits non-zero, hence the `|| true`. Standard Unity 2019 layout
  # (Encased.x86_64 + Encased_Data/, with bundled fmod/resonance/fbx
  # plugins under Encased_Data/Plugins). The Portrait Pack and
  # Run-and-Gun Kit DLC content is baked into the base Encased_Data;
  # their separate GOG installers carry only goggame-*.info license
  # stubs, so we don't fetch them.
  installer = fetchIpfs {
    cid = "QmPQL52zQWar61rF7UFQfAhemypJTEZSkhsPsXoTVvpgy6";
    fallbackUrl = "magnet:?xt=urn:btih:B2EB25CDA912119A15D8C28734F6BA288543C581";
    hash = "sha256-qvSxhl4/5UnvFODirF0r1kg9lZpXpVyZAjkcAsNd3cY=";
    name = "encased-linux-gog-55620.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "encased-data";
    version = "1.3.1517.1645";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
      python3
    ];

    # The Encased.x86_64 ELF NEEDs only libc/libstdc++/libgcc/etc.; all
    # GL/X11/audio/SDL/vulkan libs are dlopen'd by libmono and the Unity
    # engine, so they go on LD_LIBRARY_PATH at runtime. UnityPlayer.so /
    # libMonoPosixHelper.so / the standalone-player ScreenSelector.so do
    # carry NEEDED entries for gtk/glib/zlib, so add those for
    # autoPatchelf to resolve.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      gtk2
      gdk-pixbuf
      glib
      zlib
    ];

    # Encased_Data/Plugins/UnityFbxSdkNative.so links libxml2.so.2, but
    # current nixpkgs libxml2 ships SONAME libxml2.so.16 -- the old .so.2
    # ABI is gone. The FBX SDK plugin is model-import tooling the shipped
    # standalone player never dlopens during play, so let autoPatchelf
    # skip this one rather than vendoring an EOL libxml2.
    autoPatchelfIgnoreMissingDeps = [ "libxml2.so.2" ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/. "$out"/
      chmod +x "$out/Encased.x86_64"
      # Drop GOG install bookkeeping the runtime never reads.
      rm -f "$out"/goggame-*.hashdb "$out"/goggame-*.info

      # Encased_Data/Plugins/libfmodstudio.so is the only bundled object
      # shipping a PT_GNU_STACK with PF_X set (RWE). Modern kernels/glibc
      # refuse to enable an executable stack on dlopen, so FMOD audio init
      # wedges and the engine freezes on a black screen right after
      # InitializeOrResetSwapChain -- it never reaches the menu. Every
      # other bundled .so (UnityPlayer/GameAssembly/libresonanceaudio/
      # UnityFbxSdkNative) and the main Encased.x86_64 already ship RW, so
      # only this one needs the PF_X bit cleared. patchelf 0.15 has no
      # --clear-execstack, so we strip it by hand.
      python3 ${./clear-execstack.py} \
        "$out/Encased_Data/Plugins/libfmodstudio.so"

      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "encased";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "native";
  executable = "Encased.x86_64";
  # Skip the Unity standalone "select your monitor" popup; gamescope
  # already sets the resolution and fullscreens the nested window.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  env = {
    # Unity dlopens GL/X11/audio/vulkan/udev/dbus by bare name; provide
    # the full set on LD_LIBRARY_PATH. libudev.so.0 isn't shipped in
    # current nixpkgs (only .so.1), so the engine falls back to the .so.1
    # symlink that comes with systemd's udev component.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        vulkan-loader
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        wayland
        udev
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
      ]
    );
  };

  # Unity writes its config + saves (UserProfiles/) under
  # $HOME/.config/unity3d/Dark Crystal Games/Encased. runtime = "native"
  # binds $HOME to $STROM_GAMEDIR (~/.strom/encased), so this persists
  # across overlay rebuilds without an explicit relocation.
  saveLocations = [ ".config/unity3d/Dark Crystal Games/Encased" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Encased: A Sci-Fi Post-Apocalyptic RPG (Dark Crystal Games 2021, native Linux, GOG v1.3.1517.1645)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "encased";
  };
}
