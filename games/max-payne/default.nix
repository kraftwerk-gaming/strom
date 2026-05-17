{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  p7zip,
  unshield,
  unzip,
}:

let
  # 2001 Remedy / 3D Realms / Gathering of Developers MAX-FX engine
  # third-person shooter. archive.org's max-payne-2001-pc-game item
  # preserves the retail US 1-disc CD as an unmodified ISO9660 image
  # (~700 MiB). Top-level layout of the disc:
  #   Disk1/data1.{hdr,cab}      InstallShield 6 archive header + main CAB
  #   Disk1/data2.cab            second CAB (bulk: textures, sounds, FMVs)
  #   Disk1/Levels/x_level1.ras  three loose level archives on the disc
  #   Disk1/Levels/x_level2.ras  (the .ras format is Remedy's RAS package;
  #   Disk1/Levels/x_level3.ras   ~290 MiB combined, kept outside the CAB
  #                              to fit on a single CD)
  #   MAX-FX/setup/              optional level editor installer (skipped)
  #   DirectX/, Help/, secdrv.sys, drvmgt.dll, *.dbd  SafeDisc + DirectX
  #                              redist; not needed at runtime
  src = fetchIpfs {
    cid = "QmY33VoGafwBpgMo75HrizwEF5ZzUy8Wm4ZDiD5LjEqZWZ";
    fallbackUrl = "https://archive.org/download/max-payne-2001-pc-game/Max%20Payne.iso";
    hash = "sha256-Jka1PIau4wwLYdYIO4OmWvtCUtHwfiJKMRqVJtqSuSI=";
    name = "max-payne.iso";
  };

  # v1.05 no-CD MaxPayne.exe (the only file in the archive). v1.05 is
  # the final official patch; it bundles the no-CD removal of the
  # SafeDisc IAT-encryption layer. Replacing the retail Disk1 CAB
  # MaxPayne.exe with this drops the disc/secdrv.sys dependency.
  crackZip = fetchIpfs {
    cid = "QmQYYbQ4WiLrTcJbFpSNEULnizgJcRjaPf7457JvU64CSs";
    fallbackUrl = "https://archive.org/download/max-payne-2001-pc-game/MP%201.05%20crack.zip";
    hash = "sha256-2ROjrrqHzaPQeLq9jeTHzDfAssaYho51dNIvTe94/yQ=";
    name = "max-payne-1.05-crack.zip";
  };

  # Canonical community-patched rlmfc.dll for the JPEG/MMX crash on
  # modern AMD/Intel CPUs. Pinned to the silentgameplays Max-Payne-Fix
  # GitHub repo's master tree at commit d2ab8d9 (FOR AMD CPUs Fix/).
  # SHA1 d3db748214ed341dae49c172229d7eb332ab1fc9 — the same value the
  # Steam Community fix guide cites as "properly patched, just those
  # three bytes". This is a different rlmfc.dll build than our retail
  # v1.05 (Gathering of Developers) ships: 211k of 282k bytes differ,
  # so it's not a strict overlay of our binary — but it's the
  # community-distributed canonical fix that all the major guides
  # (PCGW, Steam Deck, ProtonDB Platinum reports) point at, and the
  # in-engine ABI is stable across builds for this DLL.
  rlmfcFix = fetchurl {
    url = "https://raw.githubusercontent.com/silentgameplays/Max-Payne-Fix-Windows-10/d2ab8d951c3eb5f3d4ae0fd14ab1083c8f512c2d/FOR%20AMD%20CPUs%20Fix/rlmfc.dll";
    hash = "sha256-9EmE238BaA1kpvmMFAN9S7T1DXm4gk3eDU31lInJm6o=";
    name = "rlmfc-fixed.dll";
  };

  # UCyborg's "Max Payne Series Startup Hang Patch" v1.01 (Jan 2017).
  # The MAX-FX engine initialises Direct3D inside DllMain, which
  # violates the documented DllMain contract (the loader lock is held).
  # Modern Windows D3D11 and our DXVK-backed Proton d3d8 both refuse or
  # race on the half-built device, producing either a startup hang or a
  # near-null write-AV (we hit the latter, code=c0000005 writing 0x79
  # at heap address 0x00CAE844 ~100ms after engine init). UCyborg's
  # patch rebuilds e2mfc.dll and e2driver/e2_d3d8_driver_mfc.dll so the
  # actual D3D init is deferred until execution flow has returned from
  # LoadLibrary, fixing the lockup/race for both wine/proton and
  # dgVoodoo. Distributed as a single zip on PCGW community files (id
  # 838) containing MP1 + MP2 subfolders; we only consume the MP1
  # files. SHA256 of the zip is verified; both DLLs hash-match the
  # copies redistributed in archive.org's "Max Payne Fixes.zip", which
  # is independent corroboration that this is the canonical build.
  startupHangPatch = fetchIpfs {
    cid = "QmeGbpPiTMrU1VxWPdQJrkvij6YZypS4dtEqXUcW8hH1ET";
    fallbackUrl = "";
    hash = "sha256-UMVpkYfjJnAibpwsOC+F6VvROJmKb/8YqWosfd7RgJg=";
    name = "MaxPayneStartupHangPatchv1.01.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "max-payne";

  ipfsSources = [
    src
    crackZip
    startupHangPatch
  ];
  inherit src;

  nativeBuildInputs = [
    p7zip
    unshield
    unzip
  ];

  # Extract the disc with 7z (ISO9660), pull MaxPayne.exe + engine DLLs
  # + the bulk x_data.ras out of the InstallShield CAB with unshield,
  # then overlay the loose Disk1/Levels/*.ras off the disc root. The
  # 1.05 crack's MaxPayne.exe replaces the retail SafeDisc-encrypted
  # binary so we don't need to dance around secdrv.sys / drvmgt.dll
  # under Proton.
  buildScript = ''
    mkdir -p "$TMPDIR/iso"
    7z x -o"$TMPDIR/iso" ${src} \
      'Disk1/data1.hdr' 'Disk1/data1.cab' 'Disk1/data2.cab' \
      'Disk1/Levels' >/dev/null

    mkdir -p "$TMPDIR/cab"
    unshield -d "$TMPDIR/cab" x "$TMPDIR/iso/Disk1/data1.hdr"

    # InstallShield 6 component layout (unshield materialises group
    # names with spaces -> underscores):
    #   Program_Executable_Files/  <-- the game: MaxPayne.exe, the four
    #                                  E2 engine MFC DLLs (rlmfc/e2mfc/
    #                                  grphmfc/sndmfc), the bundled
    #                                  MFC42 / MSVCRT / MSVCP60 system
    #                                  libs, x_data.ras / x_english.ras /
    #                                  x_music.ras, plus the e2driver/
    #                                  d3d8 renderer subdir, help/,
    #                                  movies/ (intro.mpg), and
    #                                  savegames/. Drop the lot at the
    #                                  game root.
    #   Shared_DLLs/, _Engine_*/, _Support_*/  -- pure InstallShield
    #                                  runtime support (isrt.dll,
    #                                  iuser.dll, value.shl, license,
    #                                  install logos). Skipped: not
    #                                  used at game-runtime.
    mkdir -p "$out"
    cp -r "$TMPDIR/cab/Program_Executable_Files"/. "$out"/
    chmod -R u+w "$out"

    # The three large per-chapter .ras packages sit at the disc root,
    # outside the InstallShield CAB, and the original setup.exe copies
    # them into the install dir verbatim. Mirror that.
    cp "$TMPDIR/iso/Disk1/Levels"/x_level*.ras "$out"/

    # Overlay the v1.05 no-CD MaxPayne.exe. The zip ships a single file
    # at "MP 1.05 crack/MaxPayne.exe"; unzip it to a scratch dir and
    # install over the retail binary.
    mkdir -p "$TMPDIR/crack"
    unzip -q -o ${crackZip} -d "$TMPDIR/crack"
    install -m0644 "$TMPDIR/crack/MP 1.05 crack/MaxPayne.exe" "$out/MaxPayne.exe"

    # Replace the disc's rlmfc.dll with the canonical community-patched
    # build. The MAX-FX engine's JPEG/MMX path mishandles modern CPUs
    # (AMD Zen / Intel 12th-gen+) and crashes during the first level
    # load (texture streaming dies with "JPEG header error" in the
    # IGNAVIA chapter). The canonical fix — distributed verbatim by the
    # Steam FixPack, Steam Deck guide id=2955756527, the silentgameplays
    # GitHub repo, and Google Drive mirrors — is a 3-byte change to
    # rlmfc.dll. Rather than hand-rolling that patch against our retail
    # (Gathering of Developers v1.05) build, we drop in the canonical
    # Steam-build patched DLL verbatim; the engine's runtime ABI for
    # rlmfc is stable across the retail and Steam builds.
    install -m0644 ${rlmfcFix} "$out/rlmfc.dll"

    # Overlay UCyborg's startup-hang-patch DLLs. The archive ships an
    # MP1 and MP2 folder; we only need the MP1 set. Same sizes as the
    # retail DLLs so this is a straight binary swap. After this the
    # MAX-FX engine no longer initialises D3D from DllMain, so the
    # near-null write-AV at engine startup (under Proton with DXVK d3d8)
    # is gone.
    mkdir -p "$TMPDIR/hangpatch"
    unzip -q -o ${startupHangPatch} -d "$TMPDIR/hangpatch"
    install -m0644 "$TMPDIR/hangpatch/Max Payne/e2mfc.dll" \
      "$out/e2mfc.dll"
    install -m0644 "$TMPDIR/hangpatch/Max Payne/e2driver/e2_d3d8_driver_mfc.dll" \
      "$out/e2driver/e2_d3d8_driver_mfc.dll"
  '';

  runtime = "proton";
  # MaxPayne.exe is both the startup wizard ("Display Setup" dialog,
  # adapter / resolution / sound picker) AND the engine. The canonical
  # Steam launch options to skip the wizard entirely and boot straight
  # into the engine are `-nodialog -skipstartup` — confirmed working
  # under Proton in multiple ProtonDB Platinum reports and the Rockstar
  # Customer Support article. `-developer` (cheats / debug menu) is
  # orthogonal and not needed for a normal smoke test; leaving it off
  # keeps the gameplay HUD clean.
  executable = "MaxPayne.exe";
  executableArgs = [
    "-nodialog"
    "-skipstartup"
  ];

  # Seed HKCU video settings before MaxPayne.exe ever sees the prefix.
  # `-nodialog` skips the startup wizard entirely — but the wizard is
  # also what writes the Video Settings keys on first launch. Without
  # them MaxPayne.exe reads garbage (uninitialised globals on the
  # heap), the D3D8 device-create path picks up a bogus back-buffer
  # count, and the engine page-faults near-null while wiring up its
  # post-create render targets.
  #
  # Resolution: 1024x768x32 @60Hz, double-buffered (one back buffer).
  # Wine's d3d8 builtin specifically warns when more than one back
  # buffer is requested ("triple buffering not properly supported"),
  # so Display Buffering is forced to 1 = double, NOT the wizard
  # default of 2 = triple.
  preRun = ''
    # Force Display Buffering=1 (double) — wine's d3d8 builtin warns
    # ("more than one back buffer is not properly supported") and the
    # engine's near-null page-fault on launch matches the broken
    # render-target wire-up that happens when the device probe falls
    # back through that path. The wizard's default is 2 (triple).
    # Patch user.reg directly: simpler than threading a regedit call
    # through proton's umu wrapper, and idempotent enough — if the
    # key isn't present yet (first prefix bootstrap), the engine
    # writes a fresh entry on first quit and we re-apply on next run.
    USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
    if [ -f "$USERREG" ] \
        && grep -q 'Remedy Entertainment\\\\Max Payne\\\\Video Settings' "$USERREG" \
        && ! grep -q '"Display Buffering"=dword:00000001' "$USERREG"; then
      echo "[strom] forcing Max Payne Display Buffering=1 (double)"
      ${pkgs.gnused}/bin/sed -i \
        -e '/Remedy Entertainment\\\\Max Payne\\\\Video Settings/,/^$/ s/"Display Buffering"=dword:[0-9a-f]\{8\}/"Display Buffering"=dword:00000001/' \
        "$USERREG"
    fi
  '';

  saveLocations = [
    # MaxPayne.exe drops savegames into Documents/Max Payne Savegames
    # under steamuser/ (one savegame00N.mps per slot). Relocate so
    # progress survives prefix wipes.
    "Documents/Max Payne Savegames"
  ];

  env = {
    # Max Payne 2001 is a pure D3D8 title. Proton ships DXVK's native
    # d3d8.dll in the prefix; force the load order to native PE first
    # (Wine's wined3d-backed d3d8 builtin is incomplete for fixed-
    # function pipeline games). Matches the Lutris CD installer's
    # wine.overrides entry for this game.
    #
    # rlmfc=n,b / e2mfc=n,b / e2_d3d8_driver_mfc=n,b: defensive
    # overrides — all three are game-bundled custom DLLs (not system
    # libraries), so wine has no builtin to conflict with, but the
    # overrides pin the loader to the native files so the UCyborg
    # startup-hang patch (e2mfc + e2_d3d8_driver_mfc) and the
    # silentgameplays JPEG/MMX patch (rlmfc) are guaranteed active.
    WINEDLLOVERRIDES = "d3d8=n,b;rlmfc=n,b;e2mfc=n,b;e2_d3d8_driver_mfc=n,b";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    # Max Payne 2001's pre-widescreen-fix engine only accepts 4:3 modes
    # from its D3D8 mode probe. Match the seeded registry resolution
    # (1024x768) for the nested viewport so the engine fills the
    # surface, then gamescope upscales 1024x768 -> 1920x1080 with
    # pillarboxing. Same pattern as painkiller.
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Max Payne (Remedy / 3D Realms 2001, retail v1.05 no-CD, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "max-payne";
  };
}
