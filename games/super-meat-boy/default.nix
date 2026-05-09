{
  self,
  lib,
  pkgs,
  fetchIpfs,
  gnutar,
  xz,
  autoPatchelfHook,
  stdenv,
}:

let
  # Linux native build of Super Meat Boy (build 3241924, +2 DLC) from
  # archive.org's Steam-Rip with Goldberg Steam Emulator already bundled.
  # The .tar.xz layout is:
  #   game/{amd64,x86}/{SuperMeatBoy, libsteam_api.so, libmariadb.so.1}
  #   game/{steam_appid.txt, steam_settings/, gamedata.dat, gameaudio.dat,
  #         resources/, Levels/, locdb.txt, README-linux.txt, ...}
  #   start.bash (top-level launcher: chdirs to game/, dispatches by uname -m)
  # Bundled libsteam_api.so is the Goldberg stub, with steam_settings/
  # populated next to it (steam_interfaces.txt, achievements.json, etc),
  # so no SteamWorks runtime is needed. RUNPATH=$ORIGIN, so libmariadb +
  # libsteam_api resolve from the binary's own directory; libSDL2,
  # libopenal, libstdc++ come from the FHS env at runtime.
  installer = fetchIpfs {
    cid = "QmZTrfvvrHGUrgUaqwvPh7g34DHPSpNTTe6ZoLP52MnTkV";
    fallbackUrl = "https://archive.org/download/super-meat-boy-linux-steam-rip/game-Super_Meat_Boy_%2B2_DLC_%28build_3241924%29_%5BLinux%2C_Steam-Rip%2C_Goldberg-Steam-Emulator%5D.tar.xz";
    hash = "sha256-srpcrzq0GQt+7hOrNp3CKSfrp+1QI2u+pxqawqIykzE=";
    name = "super-meat-boy-linux-steam-rip.tar.xz";
  };

  gameData = stdenv.mkDerivation {
    pname = "super-meat-boy-data";
    version = "build-3241924";

    dontUnpack = true;

    nativeBuildInputs = [
      gnutar
      xz
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tar -xf ${installer} -C "$out" game
      mv "$out/game"/* "$out"/
      rmdir "$out/game"
      chmod +x "$out/amd64/SuperMeatBoy" "$out/x86/SuperMeatBoy"
      # The original start.bash dispatches by uname -m and chmods the
      # game/ tree -- we don't need that since we land in $out/ directly
      # and only ship the amd64 path. Provide a tiny launcher named
      # SuperMeatBoy that the FHS env's mkGame wrapper invokes.
      cat > "$out/SuperMeatBoy" <<'EOF'
      #!/bin/sh
      here="$(dirname "$0")"
      cd "$here"
      exec "$here/amd64/SuperMeatBoy" "$@"
      EOF
      chmod +x "$out/SuperMeatBoy"
      runHook postInstall
    '';

    # The 32-bit x86 binaries fail autoPatchelf on a pure 64-bit
    # buildInputs closure (no 32-bit glibc). We only ever run the amd64
    # path, so leave the x86 deps unresolved rather than pulling in
    # multilib.
    autoPatchelfIgnoreMissingDeps = [
      "libSDL2-2.0.so.0"
      "libopenal.so.1"
    ];

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "super-meat-boy";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # Native ELF dlopens libSDL2 / libopenal / libstdc++ by bare soname;
  # FHS env exposes them via /usr/lib. libsteam_api.so + libmariadb.so.1
  # ship next to the binary and are picked up via RUNPATH=$ORIGIN.
  runtime = "custom";
  executable = "SuperMeatBoy";

  targetPkgs =
    p: with p; [
      SDL2
      openal
      libGL
      libglvnd
      mesa
      vulkan-loader
      alsa-lib
      libpulseaudio
      xorg.libX11
      xorg.libXext
      xorg.libXcursor
      xorg.libXi
      xorg.libXrandr
      xorg.libXinerama
      xorg.libXxf86vm
      xorg.libxcb
      xorg.libXScrnSaver
    ];

  env = {
    SteamAppId = "40800";
    SteamGameId = "40800";
    SDL_VIDEODRIVER = "x11";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
  };

  meta = {
    description = "Super Meat Boy (Team Meat 2010, native Linux Steam-Rip build 3241924, Goldberg)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "super-meat-boy";
  };
}
