{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  libarchive,
  pkgsi686Linux,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "empire-earth";

  # archive.org mirror of the GOG offline installer
  # (setup_empire_earth_2.0.0.14.exe) packed inside a RAR. Extract the
  # installer with bsdtar (libarchive reads RAR v4), then innoextract.
  src = fetchIpfs {
    cid = "QmedoMJTRgLNK3R4PGtKQCzzU2euwAzj4mSmXqCGkoovgY";
    fallbackUrl = "https://archive.org/download/empire.-earth.-gold.-edition.-gog/Empire.Earth.Gold.Edition.GOG.rar";
    hash = "sha256-ITbk1oz7ig7IXv5zhYpOC7FmonkoNh8laMZcDZCSRUY=";
    name = "empire-earth-gold-gog.rar";
  };

  nativeBuildInputs = [
    innoextract
    libarchive
    pkgs.python3
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/rar"
    # libarchive reads the RAR v4 container the GOG installer ships in.
    bsdtar -xf $src -C "$TMPDIR/rar" \
      'Empire.Earth.Gold.Edition.GOG/setup_empire_earth_2.0.0.14.exe'
    innoextract --gog -d "$TMPDIR/inno" \
      "$TMPDIR/rar/Empire.Earth.Gold.Edition.GOG/setup_empire_earth_2.0.0.14.exe"
    # The GOG layout nests both sub-games under app/: "Empire Earth"
    # (base) and "Empire Earth - The Art of Conquest" (the Gold default).
    mv "$TMPDIR/inno/app"/* "$out"/

    # sxlrt233.dll and Low-Level Engine.dll (LLE) are both packed with the same
    # custom packer and both declare PE ImageBase 0x10000000.  LLE imports
    # sxlrt233, so sxlrt233 loads first and claims 0x10000000; LLE is then
    # forced to relocate.  LLE's packer decompressor stub has hardcoded
    # absolute refs that assume its own base is 0x10000000; when relocated
    # those refs corrupt the global array-pointer table and the first
    # worker-thread read faults (page fault on read at 0x00000000 inside LLE).
    #
    # Fix: set the DYNAMIC_BASE (ASLR, 0x0040) bit in sxlrt233's PE Optional
    # Header DllCharacteristics.  Wine's loader then picks a random base for
    # sxlrt233, applies its complete .reloc section (9655 HIGHLOW entries), and
    # leaves 0x10000000 free for LLE.  The ImageBase field stays 0x10000000 so
    # the relocation delta is computed correctly; only the 2-byte
    # DllCharacteristics word changes on disk.
    python3 ${./patch-sxlrt233.py} \
      "$out/Empire Earth/sxlrt233.dll" \
      "$out/Empire Earth - The Art of Conquest/sxlrt233.dll"
  '';

  runtime = "proton";

  # Art of Conquest is the Gold Edition entry point (base game + expansion).
  executable = "Empire Earth - The Art of Conquest/EE-AOC.exe";

  # Empire Earth (a DirectDraw7/Direct3D7 engine, DX7HRDisplay.dll) writes
  # its saves to Data/Saved Games next to the binary, which lands in the
  # per-game fuse-overlayfs upper (persisted via $STROM_GAMEDIR) rather than
  # under drive_c/users/steamuser/...
  saveLocations = [ ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  env = {
    # DX7-era DirectDraw/Direct3D; wined3d translates it more faithfully
    # than DXVK, which has no ddraw path of its own.
    PROTON_USE_WINED3D = "1";
    WINEDLLOVERRIDES = "ddraw=b";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
    # Report a single logical CPU to the game (mapped to host CPU 0). The
    # 2001 engine spins up per-CPU worker threads and one of them races on a
    # not-yet-populated global table in Low-Level Engine.dll, reading through
    # a NULL base:
    #   page fault on read at 0x00e4ef99: mov eax,[ecx+eax*4]  ECX=EAX=0
    #   (ECX = *(0x1010fc8c), the array base, still NULL)
    # The race only loses under WINEDEBUG tracing here; untraced runs survive.
    # WINE_CPU_TOPOLOGY=1:0 makes ntdll report a single processor so the
    # engine spawns one worker and the race window closes -- the engine-level
    # form of the community "start /affinity 1" launch fix, kept as a
    # defensive measure for slower hardware.
    WINE_CPU_TOPOLOGY = "1:0";
  };

  # EE-AOC.exe (the Art of Conquest expansion) aborts at startup with
  #   "Empire Earth: Art of Conquest requires the original Empire Earth
  #    game in order to run. Empire Earth cannot be found. Please install
  #    or reinstall Empire Earth."
  # because it locates the base game via the registry, which innoextract
  # never wrote: it only unpacks files, it does NOT run the GOG installer's
  # [Registry] section. The EXE reads HKCU\Software\SSSI\Empire Earth and
  # forms a path from "Installed From Volume" + "Installed From Directory" +
  # "Empire Earth.exe"; if that file is absent it bails (the key name and
  # both value names are literal strings inside EE-AOC.exe).
  #
  # The engine's own Mad Doc EE-AOC key, written on a previous launch, shows
  # the split it expects: Volume="Z:", Directory="\tmp\.strom-overlay\" (a
  # leading and trailing backslash, NO drive letter in Directory). So the
  # base game at $STROM_OVERLAY/Empire Earth (Z: maps to /) must be seeded as
  # Volume="Z:", Directory="\tmp\.strom-overlay\Empire Earth\" — concatenated
  # that yields Z:\tmp\.strom-overlay\Empire Earth\Empire Earth.exe.
  #
  # preRun runs inside the sandbox right before proton starts; wineserver
  # merges the key into HKCU when it loads user.reg at the following launch.
  # (The worker-thread race past this check is mitigated by WINE_CPU_TOPOLOGY
  # in env, above.)
  #
  # The expansion's render settings live under Mad Doc Software\EE-AOC. The
  # engine writes them itself once it has run, but on a fresh prefix we seed
  # a 1920x1080 32-bit window so the menu fills gamescope and renders in
  # colour: the setup_is6.iss notes the menu draws solid white whenever Game
  # Bit Depth != Texture Bit Depth, and the GOG default leaves them at 16-bit
  # 800x600. "Rasterizer Name"="Direct3D" picks the DX7HRDisplay.dll plugin
  # (vs. the "Direct3D Hardware TnL" DX7HRTnLDisplay.dll). (No
  # DirectDrawRenderer override: wined3d's accelerated ddraw path renders the
  # menu; the GDI software path produced a blank surface.)
  #
  # CWD must be the AoC folder, NOT the overlay root. At startup LLE imports
  # GetCurrentDirectoryA and scans the CURRENT DIRECTORY for "*.dll", calling
  # each match's RPIMGetRasterizer export to enumerate display plugins into the
  # GERasterizer::sRasterizers vector. The strom inner cd's to $STROM_OVERLAY
  # (the GOG install root), which holds NO DX7HR*.dll — only the GOG-installer
  # leftover GameuxInstallHelper.dll. So the scan finds no rasterizer (and
  # faults trying to call RPIMGetRasterizer on GameuxInstallHelper), leaving
  # sRasterizers empty; the next GERasterizer::GetRasterizer() reads the NULL
  # table base at 0x1010fc8c and the engine page-faults on read at 0:
  #   1000ef99  mov ecx,[0x1010fc8c] ; mov eax,[ecx+eax*4]  ECX=EAX=0
  # cd'ing into the AoC subdir (which DOES hold DX7HRDisplay.dll +
  # DX7HRTnLDisplay.dll) before the proton exec — preRun runs in the inner
  # shell right before `exec`, so the CWD is inherited — makes the scan find
  # the plugins, populate sRasterizers, and the engine reaches the menu.
  preRun = ''
    cd "$STROM_OVERLAY/Empire Earth - The Art of Conquest"
    reg_file="$STROM_COMPATDATA/0/pfx/user.reg"
    if [ ! -f "$reg_file" ]; then
      printf 'WINE REGISTRY Version 2\n\n' > "$reg_file"
    fi
    if ! grep -q 'Software\\\\SSSI\\\\Empire Earth' "$reg_file" 2>/dev/null; then
      printf '\n[Software\\\\SSSI\\\\Empire Earth]\n"Installed From Volume"="Z:"\n"Installed From Directory"="\\\\tmp\\\\.strom-overlay\\\\Empire Earth\\\\"\n' \
        >> "$reg_file"
    fi
    if ! grep -q 'Software\\\\Mad Doc Software\\\\EE-AOC' "$reg_file" 2>/dev/null; then
      printf '\n[Software\\\\Mad Doc Software\\\\EE-AOC]\n"Rasterizer Name"="Direct3D"\n"Game Window Width"=dword:00000780\n"Game Window Height"=dword:00000438\n"Game Bit Depth"=dword:00000020\n"Texture Bit Depth"=dword:00000020\n' \
        >> "$reg_file"
    fi
  '';

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
    pkgs.libxau
    pkgs.libxdmcp
    pkgs.alsa-lib
    pkgs.libpulseaudio
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
    pkgsi686Linux.libxau
    pkgsi686Linux.libxdmcp
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Empire Earth: Gold Edition (Art of Conquest, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "empire-earth";
  };
}
