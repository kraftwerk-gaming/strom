{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchzip,
  p7zip,
  pkgsi686Linux,
  runCommandLocal,
  unshield,
}:

let
  gameISO = fetchIpfs {
    cid = "QmWMS4zhvCMj5Nz3gpcaDbgChsZZR6ULY9z9aNcHakuaBR";
    fallbackUrl = "https://archive.org/download/anno-1602-ge-uk/ANNO1602_GE_UK.ISO";
    hash = "sha256-1S9EHCh0j8bioB7QKechOaWwADVTEHQXAOuXWArU5vM=";
    name = "anno-1602-ge-uk.iso";
  };

  # No-CD patched executable. The retail Gold Edition checks for the disc at
  # runtime; this replaces 1602.exe with a patched build that does not.
  noCdArchive = fetchIpfs {
    cid = "QmWAc3pDNQrvngxjcBCqNV8LyxCdFcSqSq2kW1K3kKh9MW";
    fallbackUrl = "https://archive.org/download/anno-1602-ge-uk/1602NOCD.7z";
    hash = "sha256-x81umVKnIr/jhaBrucAXP6iMH6PmYOEz9Fon6XpVt64=";
    name = "1602nocd.7z";
  };

  # FunkyFr3sh's cnc-ddraw: a community DDraw->OpenGL/D3D9 replacement
  # designed for old Windows games on Linux/Wine. Wined3d's DDraw path is
  # broken on Mesa-Intel (Optimus laptops), so we ship cnc-ddraw as a
  # loose ddraw.dll override instead of relying on PROTON_USE_WINED3D.
  # https://github.com/FunkyFr3sh/cnc-ddraw
  cncDdraw = fetchzip {
    url = "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/v7.1.0.0/cnc-ddraw.zip";
    hash = "sha256-BGZ+7wsreutuKDdp6IjszIAHJyuxDjbor0O3Z3xDy2Q=";
    stripRoot = false;
    name = "cnc-ddraw-v7.1.0.0";
  };

  # Newer SmackW32.dll (v3.1n) than the v3.1b shipped with Anno 1602.
  # The retail DLL hangs and double-plays cutscenes under modern Wine;
  # this revision (extracted from a Diablo II install) is more reliable.
  smackerDll = fetchIpfs {
    cid = "bafkreid7lxtov7z6aj74dp5fvwh2rtxs56o6tj6v7q4n6rtyqwcaripmgi";
    # No archive.org fallback: this DLL is sourced from a Diablo II install
    # and only re-hosted via IPFS in this repo.
    fallbackUrl = "";
    hash = "sha256-f13m6v8+An/Bv6Wtj6jO8u+d6afV/DjfRniFhAih7DI=";
    name = "smackw32-from-d2.dll";
  };

  # The retail ISO has the bulk of the game packed in InstallShield CAB
  # archives (data1.cab/data2.cab) plus a few loose directories (MUSIC8,
  # VIDEOSMK). We extract the CAB's "Eng" component directly with unshield,
  # then merge the loose dirs and overlay the no-CD executable. This avoids
  # running the InstallShield setup under Wine, which is non-trivial to
  # drive non-interactively.
  gameData =
    runCommandLocal "anno-1602-ad-data"
      {
        nativeBuildInputs = [
          p7zip
          unshield
        ];
      }
      ''
        mkdir -p /tmp/iso
        7z x ${gameISO} -o/tmp/iso

        mkdir -p /tmp/cab
        unshield -d /tmp/cab x /tmp/iso/data1.hdr

        # "Eng" is the InstallShield component containing the English game
        # files (1602.EXE, GFX, scripts, etc).
        cp -r /tmp/cab/Eng "$out"
        chmod -R u+w "$out"

        # Merge loose data directories from the ISO root.
        cp -r /tmp/iso/Anno1602/MUSIC8 "$out"/MUSIC8
        cp -r /tmp/iso/Anno1602/VIDEOSMK "$out"/VIDEOSMK

        # Overlay no-CD patched 1602.exe (lowercase). Drop the original
        # uppercase 1602.EXE so only the patched binary remains.
        rm -f "$out"/1602.EXE
        7z x -y -o"$out" ${noCdArchive}

        # Overlay newer SmackW32.dll for more reliable intro/cutscene
        # playback under Wine. The retail SMACKW32.DLL is uppercase; both
        # case variants would shadow each other on Wine's case-insensitive
        # FS, so remove the original first.
        rm -f "$out"/SMACKW32.DLL "$out"/SmackW32.dll "$out"/smackw32.dll
        cp ${smackerDll} "$out"/SmackW32.dll

        # Drop cnc-ddraw's ddraw.dll in next to 1602.exe. The retail game
        # has no shipped ddraw.dll, but defensively strip any case variants
        # before copying so the loose override is unambiguous on Wine's
        # case-insensitive FS.
        rm -f "$out"/ddraw.dll "$out"/Ddraw.dll "$out"/DDraw.dll "$out"/DDRAW.DLL
        cp ${cncDdraw}/ddraw.dll "$out"/ddraw.dll
      '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "anno-1602-ad";

  ipfsSources = [
    gameISO
    noCdArchive
    smackerDll
  ];
  src = gameData;
  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # next to its binary, not under drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "1602.exe";
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags."--expose-wayland" = true;
    # Anno's edge-scroll is mouse-position-based. Without grab, gamescope's
    # cursor mapping during fast motion produces phantom right-edge events.
    flags."--force-grab-cursor" = true;
  };

  env = {
    # 1602 uses DDraw, not D3D. We ship FunkyFr3sh's cnc-ddraw next to the
    # binary as a loose ddraw.dll; tell Wine to load our native override
    # before falling back to its builtin (wined3d's DDraw path is broken
    # on Mesa-Intel Optimus hosts).
    WINEDLLOVERRIDES = "ddraw=n,b";
    PULSE_LATENCY_MSEC = "60";
  };

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
    pkgs.python3
    pkgs.mesa
    pkgs.vulkan-loader
    pkgs.libGL
    pkgs.libx11
    pkgs.libxext
    pkgs.libxcb
    pkgs.libxcursor
    pkgs.libxrandr
    pkgs.libxi
    pkgs.libxfixes
    pkgs.libxrender
    pkgs.libxcomposite
    pkgs.libxinerama
    pkgs.libxxf86vm
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.openal
    pkgs.systemd
    pkgsi686Linux.freetype
    pkgsi686Linux.glibc
    pkgsi686Linux.glib
    pkgsi686Linux.libx11
    pkgsi686Linux.libxext
    pkgsi686Linux.libxcb
    pkgsi686Linux.libxcursor
    pkgsi686Linux.libxrandr
    pkgsi686Linux.libxi
    pkgsi686Linux.libxfixes
    pkgsi686Linux.libxrender
    pkgsi686Linux.libxcomposite
    pkgsi686Linux.libxinerama
    pkgsi686Linux.libxxf86vm
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  # Anno 1602 polls DirectInput joysticks and any non-zero axis turns
  # into constant edge-scrolling (typically to the right). Hide all
  # joystick / evdev devices from the sandbox to suppress this.
  bwrap.tmpfs = [ "/dev/input" ];

  meta = {
    description = "Anno 1602 A.D. Gold Edition (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "anno-1602-ad";
  };
}
