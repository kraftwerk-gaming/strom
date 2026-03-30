{
  callPackage,
  lib,
  pkgs,
  fetchurl,
  p7zip,
  pkgsCross,
  runCommandLocal,
}:

let
  mkGame = import ../../lib/mk-game.nix { inherit lib pkgs; };
  proton = callPackage ../../lib/patched-proton.nix { };

  # ASI mod that fixes AB-BA deadlock on CS@00864F00 during track loading.
  deadlockFix =
    runCommandLocal "nfsu2-deadlock-fix"
      {
        nativeBuildInputs = [ pkgsCross.mingw32.buildPackages.gcc ];
      }
      ''
        mkdir -p "$out"
        i686-w64-mingw32-gcc -shared -o "$out/DeadlockFix.asi" ${./deadlock-fix.c} \
          -nostdlib -lkernel32 -Wl,--enable-stdcall-fixup,-e,__DllMainCRTStartup
      '';
in
mkGame {
  name = "nfs-underground-2";

  src = fetchurl {
    url = "https://archive.org/download/NFSU2Stable/Need%20for%20Speed%20Underground%202.7z";
    hash = "sha256-aC+1gcJLFay2jWTDBOXZSL3tIxaBoDHV1amtl82XBlA=";
    name = "nfsu2.7z";
  };

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x $src -o"$out"

    if [ -d "$out/Need for Speed Underground 2" ]; then
      mv "$out/Need for Speed Underground 2"/* "$out"/
      rmdir "$out/Need for Speed Underground 2"
    fi

    # Patch serial port Sleep(0) spinloops in SPEED2.EXE
    chmod u+w "$out/SPEED2.EXE"
    for offset in \
      0x35772b 0x35774a \
      0x35098d 0x350a0a 0x350f5c 0x350f8f \
      0x3571ee 0x3578cc 0x357d61 0x357d7b 0x357fdc \
      0x1fa3a4 0x243ce5 0x243d45 0x2d8891 0x2da440 0x34a15f; do
      printf '\x90\x90' | dd of="$out/SPEED2.EXE" bs=1 seek=$(($offset)) conv=notrunc 2>/dev/null
    done
    chmod u-w "$out/SPEED2.EXE"


    # Install deadlock fix ASI mod
    cp ${deadlockFix}/DeadlockFix.asi "$out/SCRIPTS/DeadlockFix.asi"
  '';

  # SPEED2.EXE must be a copy - game resolves its path through symlinks
  # and uses it as the base directory for saves/configs
  # EXE and DLLs must be copies - Wine resolves symlinks and the game
  # uses the resolved path as its base directory for saves/configs
  copyGlobs = [ ];

  runtime = "proton";
  executable = "SPEED2.EXE";
  gamescopeArgs = "-W 1920 -H 1080 -w 1920 -h 1080 -r 60 --immediate-flips --expose-wayland";

  env = {
    STEAM_COMPAT_CONFIG = "sdlinput";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    DXVK_ASYNC = "1";
    PULSE_LATENCY_MSEC = "60";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  preRun = "";

  meta = {
    description = "Need for Speed: Underground 2 (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "nfs-underground-2";
  };
}
