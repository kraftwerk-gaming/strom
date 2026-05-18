{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Company of Heroes (Relic 2006 / THQ), the original retail PC release.
  # archive.org item `company-of-heroes-2006-thq-relic-dvd` ships the
  # disc as a 7z wrapping a single 4.6 GiB UDF DVD image (Disc01.iso).
  # The disc lays the full install tree out under
  #   program files/THQ/Company of Heroes/
  # alongside the AutoRun/Setup/Manual files - so we don't have to run
  # the InstallShield MSI. Pulling RelicCOH.exe + the WW2/Engine/RelicOnline
  # SGA archives straight out of the UDF gets us a working install
  # without wine ever touching the prefix at build time.
  #
  # SecuROM disc-check: the retail 2006 build's runtime DRM is satisfied
  # by the disc-image-derived data files alone (PCGW / CodeWeavers both
  # note the game does not require the CD in the drive at play time).
  src = fetchIpfs {
    cid = "QmNiJYfpVaaYC5DjV3b1c7Cpe8iLyLQxTWLeKB1d6pX8qv";
    fallbackUrl = "https://archive.org/download/company-of-heroes-2006-thq-relic-dvd/Company.of.Heroes.2006.THQ.Relic.DVD.7z";
    hash = "sha256-tRW8tvK1RHkKw41XbU58v4WuNiUPfDCyITm3BTBgA7U=";
    name = "company-of-heroes-2006-dvd.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "company-of-heroes";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  # Two-stage extract: 7z -> Disc01.iso, then 7z (UDF) -> the
  # `program files/THQ/Company of Heroes/` subtree flattened to $out.
  # We skip the DVD's installer chrome (AutoRun.exe, Setup.exe,
  # Company of Heroes.msi, AcroSetup.exe, DarkCrusadeDemo.exe,
  # backgrounds/, etc.) - none of it is needed at runtime.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/disc" "$TMPDIR/iso"
    7z x -y "$src" -o"$TMPDIR/disc" \
      'Company.of.Heroes.2006.THQ.Relic.DVD/Disc01/Disc01.iso' >/dev/null
    iso="$TMPDIR/disc/Company.of.Heroes.2006.THQ.Relic.DVD/Disc01/Disc01.iso"
    7z x -y "$iso" -o"$TMPDIR/iso" 'program files/THQ/Company of Heroes/*' >/dev/null
    cp -r "$TMPDIR/iso/program files/THQ/Company of Heroes"/. "$out"/
    chmod -R u+w "$out"

    # The retail DVD's InstallShield writes Locale.ini at install time
    # to pick the localized .ucs / WW2Locale-<lang>.sga pair. Since we
    # skip the installer and copy the install tree straight off the
    # DVD, the file is missing and RelicCOH.exe aborts on first launch
    # with "GAME -- Failed to load 'Locale.ini'" / "GlobalInit -- Failed
    # load for step: 'Config File'" (logged to <gamedir>/warnings.log).
    # The English DVD ships Engine/Locale/English/ and
    # WW2/Archives/WW2Locale-English.sga, so seed the English locale.
    #
    # CRITICAL: RelicCOH's INI parser only accepts CRLF line endings.
    # An LF-only Locale.ini is silently rejected with the same "Failed
    # to load" error as a missing file - confirmed by bytes-diffing
    # against the InstallShield-generated original. Use \r\n.
    printf '[locale]\r\nlang=English\r\n' >"$out/Locale.ini"
  '';

  runtime = "proton";
  executable = "RelicCOH.exe";

  saveLocations = [
    # Relic Essence engine writes savegames, profiles and the
    # RelicCOH.ini config under Documents/My Games/Company of Heroes/
    # (subtree includes Savegames/RelicCOH/Campaigns/, Players/, etc.).
    # Relocating the whole dir keeps user progress alive across
    # wineprefix wipes.
    "Documents/My Games/Company of Heroes"
  ];

  env = {
    # Relic Essence is a 32-bit engine; LAA lets the game address >2 GiB
    # of virtual memory, which the engine asks for when streaming the
    # WW2Art/WW2Sound SGAs at high quality. RelicCOH.exe already has the
    # IMAGE_FILE_LARGE_ADDRESS_AWARE bit set in its PE header (verified
    # via offset 0x116 -> Characteristics = 0x122), so this env is mostly
    # belt-and-braces for wine's force-LAA path.
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # Synthesize a fake /proc/meminfo with non-zero SwapTotal so the
  # Essence engine's "Not enough virtual memory" startup check passes.
  #
  # COH computes pagefile = ullTotalPageFile - ullTotalPhys and aborts
  # with "Your system total paging files must be at least 768MB" (ucs
  # string 304) / "LoadDevicesInit -- Failed load for step: 'System
  # Tests'" when the result is below ~768 MiB. Wine derives
  # ullTotalPageFile from /proc/meminfo's MemTotal+SwapTotal
  # (dlls/ntdll/unix/system.c: TotalCommitLimit = (totalram+totalswap)/
  # page_size), so a swap-less host yields pagefile = 0 and the game
  # logs "63584MB RAM, 0MB Pagefile" / "Application failed to initialize
  # it's devices, code: 2" in warnings.log.
  #
  # Wine has no env knob for the page-file figure (kernelbase/memory.c
  # GlobalMemoryStatusEx reads /proc/meminfo unconditionally), so the
  # cleanest contained fix is to rewrite SwapTotal/SwapFree in a copy of
  # the host meminfo and ro-bind that file over /proc/meminfo inside the
  # bwrap sandbox. The bind has to happen AFTER bwrap's `--proc /proc`
  # (otherwise --proc overlays the whole /proc and wipes our file
  # bind), so it goes through BWRAP_ARGS which lib/bwrap.nix splices in
  # after the typed args. 2 GiB is well above COH's 768 MiB threshold
  # and matches what a typical Windows install carves for the page file.
  bwrap.extraPreHook = ''
    __coh_meminfo="$STROM_CACHEDIR/meminfo"
    awk '
      /^SwapTotal:/ { print "SwapTotal:       2097152 kB"; next }
      /^SwapFree:/  { print "SwapFree:        2097152 kB"; next }
      { print }
    ' /proc/meminfo >"$__coh_meminfo"
    BWRAP_ARGS="''${BWRAP_ARGS:-} --ro-bind $__coh_meminfo /proc/meminfo"
    export BWRAP_ARGS
  '';

  # Materialize Locale.ini into the fuse-overlayfs upper layer
  # ($STROM_GAMEDIR) before the merge mount goes up. The buildScript
  # seeds the file in the read-only lower for standalone-build
  # correctness; surfacing the same file in the upper guarantees that
  # the game sees a writable, locally-cached copy even on environments
  # where the merged view of lower-only files behaves oddly.
  copyGlobs = [ "Locale.ini" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Essence engine uses DirectInput relative mouse for camera pan;
      # under nested Xwayland an explicit cursor grab keeps the RTS
      # scroll-edge detection from skipping when the pointer leaves the
      # virtual display.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Company of Heroes (Relic 2006 retail DVD, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "company-of-heroes";
  };
}
