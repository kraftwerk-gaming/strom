{
  self,
  lib,
  pkgs,
  fetchIpfs,
  bchunk,
  p7zip,
  unar,
  unshield,
}:

let
  # 2003 Remedy / Rockstar MAX-FX 2 engine third-person shooter, the
  # direct sequel to Max Payne (2001) sharing the same engine family.
  # DEViANCE scene release of the 2-CD retail (CD1 install disc + CD2
  # play disc). Layout is nested archives:
  #
  #   MAX.PAYNE.2.../CD1/dev-mp2a.{rar,r00..r54}  multi-volume RAR for CD1
  #   MAX.PAYNE.2.../CD2/dev-mp2b.{rar,r00..r48}  multi-volume RAR for CD2
  #   MAX.PAYNE.2.../deviance.nfo                 release info
  #
  # Each multi-volume RAR unpacks to a single MODE1/2352 BIN+CUE pair
  # (MP2_Install.bin / MP2_Play.bin). The two discs combine into one
  # InstallShield 6 set:
  #   CD1: data1.{hdr,cab} + data2.cab (boot CABs + first bulk volume)
  #   CD2: data3.cab (third CAB volume, ~616 MiB of textures/movies)
  #        + crack/MaxPayne2.exe (no-SecuROM patched game binary)
  #
  # bchunk converts each BIN to ISO9660, 7z pulls the InstallShield
  # parts and the crack out of the ISOs, unshield extracts the merged
  # 3-CAB set in a single pass (Main file group = the entire game
  # payload), and the cracked MaxPayne2.exe overlays the retail
  # SecuROM-wrapped binary at the end. SecuROM under Proton spawns a
  # TRACE-thread debugger detector that wedges the process on launch;
  # the DEViANCE crack strips the wrapper.
  src = fetchIpfs {
    cid = "QmbL7JDhPYzV4tR7RR4y9jxWbEKcvgCL9wWFM67VUFKS4D";
    fallbackUrl = "https://archive.org/download/max.payne.2.the.fall.of.max.payne-deviance./MAX.PAYNE.2.THE.FALL.OF.MAX.PAYNE-DEViANCE.rar";
    hash = "sha256-3mham4CN7WXBN9a7J/OjHsWZmc2OZYL+mBw+hAOVsXg=";
    name = "max-payne-2-deviance.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "max-payne-2-the-fall-of-max-payne";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    bchunk
    p7zip
    unar
    unshield
  ];

  # Three-stage extraction:
  #   1. unar peels the outer rar (DEViANCE wrapper), giving the two
  #      multi-volume rar sets under MAX.PAYNE.2.../CD1/ and CD2/.
  #   2. unar again on each inner set yields MP2_Install.bin/cue and
  #      MP2_Play.bin/cue (raw CD images, MODE1/2352).
  #   3. bchunk converts each BIN to an ISO9660 track.iso, 7z pulls the
  #      InstallShield files out (data{1.hdr,1.cab,2.cab} from CD1,
  #      data3.cab + crack/MaxPayne2.exe from CD2), unshield walks the
  #      merged 3-CAB set picking only the "Main" file group, then the
  #      cracked binary overlays the retail one.
  buildScript = ''
    mkdir -p "$TMPDIR/outer"
    unar -q -o "$TMPDIR/outer" "$src"
    release="$TMPDIR/outer/MAX.PAYNE.2.THE.FALL.OF.MAX.PAYNE-DEViANCE"

    mkdir -p "$TMPDIR/cd1" "$TMPDIR/cd2"
    unar -q -D -o "$TMPDIR/cd1" "$release/CD1/dev-mp2a.rar"
    unar -q -D -o "$TMPDIR/cd2" "$release/CD2/dev-mp2b.rar"

    # bchunk wants cue + bin sharing a basename in the same directory.
    bchunk "$TMPDIR/cd1/MP2_Install.bin" "$TMPDIR/cd1/MP2_Install.cue" \
      "$TMPDIR/cd1/iso_" >/dev/null
    bchunk "$TMPDIR/cd2/MP2_Play.bin" "$TMPDIR/cd2/MP2_Play.cue" \
      "$TMPDIR/cd2/iso_" >/dev/null

    # InstallShield 6 expects data1.hdr / data1.cab / data2.cab / data3.cab
    # all in the same directory. Pull the boot pair + bulk vol 2 off CD1
    # and bulk vol 3 off CD2, then unshield against data1.hdr.
    mkdir -p "$TMPDIR/cab"
    7z x -o"$TMPDIR/cab" "$TMPDIR/cd1/iso_01.iso" \
      data1.hdr data1.cab data2.cab >/dev/null
    7z x -o"$TMPDIR/cab" "$TMPDIR/cd2/iso_01.iso" \
      data3.cab >/dev/null

    # The DEViANCE no-SecuROM MaxPayne2.exe is at the disc root of CD2
    # under crack/. The retail Install disc's SecuROM-wrapped binary
    # gets dropped by InstallShield into the Main component; we
    # overwrite it after unshield runs.
    7z x -o"$TMPDIR/crack" "$TMPDIR/cd2/iso_01.iso" 'crack/MaxPayne2.exe' >/dev/null

    # The retail MP2 InstallShield project keeps all the game payload
    # under a single "Main" file group: MaxPayne2.exe + BugReport.exe,
    # the engine MFC DLLs (e2mfc / grphmfc / sndmfc / rlmfc plus the
    # X_*MFC / T_*MFC / KF2MFC / PSysLibMFC sublibs), the bundled
    # MFC71 / MSVCP71 / MSVCR71 runtimes, eax.dll, the e2driver/
    # render-backend subdir, the MP2_*.ras package files (Data,
    # English, Init, Levels_A/B/C, Music, Sounds), oleacc.dll,
    # SysInfo.dll, and the help/ + movies/ + savegames/ stubs.
    # Everything else in data1.hdr is InstallShield Support/Engine
    # scaffolding (StrTbl, RunTime, kernel placeholder, etc.) and
    # WinSysDir holds redundant copies of the MFC/MSVC redists --
    # skipped both.
    mkdir -p "$TMPDIR/unshield"
    unshield -g Main -d "$TMPDIR/unshield" x "$TMPDIR/cab/data1.hdr" >/dev/null

    mkdir -p "$out"
    cp -r "$TMPDIR/unshield/Main"/. "$out"/
    chmod -R u+w "$out"

    # Overlay the DEViANCE no-CD MaxPayne2.exe over the retail SecuROM
    # binary InstallShield just installed (1486848 B cracked vs 2669317 B
    # retail).
    install -m0644 "$TMPDIR/crack/crack/MaxPayne2.exe" "$out/MaxPayne2.exe"
  '';

  runtime = "proton";
  # The retail InstallShield project installs the engine binary with
  # CamelCase: MaxPayne2.exe (alongside MaxPayne2.ico, MaxPayne2.cfg).
  executable = "MaxPayne2.exe";
  # MaxPayne2.exe is both the startup wizard ("Display Setup" dialog,
  # adapter / resolution / sound picker) AND the engine. `-nodialog
  # -skipstartup` are the canonical Remedy launch flags (verified
  # present as bare strings in MaxPayne2.exe at offsets 0xe6a40 /
  # 0xe69cc respectively, sitting in the same argv keyword table as
  # `-developer`, `-window`, `-screenshot`, `-debugmem` etc.).
  #
  # But -- unlike MP1 -- MP2's engine refuses to boot into the game
  # when the registry is empty: it falls back to the startup wizard
  # even with -nodialog, because the post-skip path reads
  # HKCU\Software\Remedy Entertainment\MaxPayne2\Video Settings
  # immediately and aborts if Display Width / Height / Bits Per Pixel
  # / HW Acceleration Level / Driver are missing (those exact value
  # names are at 0xe7d90..0xe7df0 in MaxPayne2.exe, read via RegOpenKey
  # against the parent path stored at 0xe62f8 / 0xe6310). The wizard
  # is what writes those keys on first launch, so on a fresh prefix
  # -nodialog deadlocks against itself. The fix is to pre-seed the
  # registry before MaxPayne2.exe ever runs -- same idea as MP1's
  # Display Buffering seed, just a bigger value set.
  executableArgs = [
    "-nodialog"
    "-skipstartup"
  ];

  # Seed HKCU\Software\Remedy Entertainment\MaxPayne2\{Video,Audio}
  # Settings before MaxPayne2.exe sees the prefix.
  #
  # `-nodialog` skips the startup wizard entirely -- but the wizard
  # is what populates these keys on first launch. Without them the
  # engine bails to the wizard anyway (the launcher we are trying
  # to bypass), so on a fresh prefix the flag is a no-op.
  #
  # Values (1920x1080x32, Hardware T&L, D3D driver) match the
  # gamescope nested-width/height in this recipe; the in-engine mode
  # probe under DXVK exposes 1920x1080 as a standard mode.
  #
  # MAX-FX engine registry value reference (verified by `strings` on
  # MaxPayne2.exe in this build):
  #   "Display Width"          dword  pixel width
  #   "Display Height"         dword  pixel height
  #   "Display Bits Per Pixel" dword  32 (0x20)
  #   "HW Acceleration Level"  dword  2 = Hardware T&L (vs 1 SW T&L)
  #   "Driver"                 sz     "D3D" (vs "Reference")
  #   "CPU Driver"             sz     CPU brand (Intel/AMD label)
  #
  # The same `feedback_prerun_userreg_bootstrap.md` lesson from MP1
  # applies: proton creates user.reg AFTER preRun runs on first
  # launch, so we cannot guard with `[ -f $USERREG ]` -- we have to
  # bootstrap the file if absent. After first launch (when proton
  # writes the boilerplate user.reg with WINE REGISTRY Version 2 +
  # the standard `#arch=win64` header), the patcher converges to
  # idempotent append-only behaviour.
  preRun = ''
        USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
        mkdir -p "$(dirname "$USERREG")"
        if [ ! -f "$USERREG" ]; then
          echo "[strom] bootstrapping user.reg for MaxPayne2 video-settings seed"
          cat > "$USERREG" <<'__EOF__'
    WINE REGISTRY Version 2
    ;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

    __EOF__
        fi
        if ! grep -q 'Remedy Entertainment\\\\MaxPayne2\\\\Video Settings' "$USERREG"; then
          echo "[strom] seeding MaxPayne2 Video Settings (1920x1080x32, Hardware T&L, D3D)"
          cat >> "$USERREG" <<'__EOF__'

    [Software\\Remedy Entertainment\\MaxPayne2\\Video Settings] 1063280400
    "Display Width"=dword:00000780
    "Display Height"=dword:00000438
    "Display Bits Per Pixel"=dword:00000020
    "HW Acceleration Level"=dword:00000002
    "Driver"="D3D"
    "CPU Driver"="Intel Pentium 4"

    [Software\\Remedy Entertainment\\MaxPayne2\\Audio Settings] 1063280400
    "Sound Quality"=dword:00000002
    "Sound Channels"=dword:00000020

    __EOF__
        fi
  '';

  saveLocations = [
    # MaxPayne2.exe drops savegames into Documents/Max Payne 2 Savegames
    # under steamuser/ (one savegame00N.mp2s per slot). Relocate so
    # progress survives prefix wipes.
    "Documents/Max Payne 2 Savegames"
  ];

  env = {
    # MP2 is a D3D8 title (despite the in-game error string mentioning
    # "DirectX 9" -- the engine actually calls Direct3DCreate8, and
    # ships its own e2_d3d8_driver_mfc.dll). Pin DXVK's native d3d8.dll
    # over wine's builtin to match the silentgameplays Win10 fix's
    # WINEDLLOVERRIDES recommendation; the engine's fixed-function
    # rendering path exercises corners of d3d8 that wine's wined3d
    # builtin still mishandles.
    WINEDLLOVERRIDES = "d3d8=n,b";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    # Engine probes D3D8 display modes at init (despite the error
    # message about "DirectX 9" -- MaxPayne2.exe imports
    # Direct3DCreate8 from d3d8.dll); 1920x1080 is in the standard
    # mode set DXVK exposes. If the in-game mode picker can't find
    # the native res during interactive testing, fall back to
    # 1280x1024 + gamescope upscale.
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Max Payne 2: The Fall of Max Payne (2003 Remedy / Rockstar, DEViANCE no-CD, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "max-payne-2-the-fall-of-max-payne";
  };
}
