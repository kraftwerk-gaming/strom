{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "max-payne";

  # The installed game, pinned as one reproducible tar.zst bundle: the
  # desktop extracts it into the overlay base and the Android client into
  # its game directory, from the same CID.
  #
  # Provenance. 2001 Remedy / 3D Realms / Gathering of Developers MAX-FX
  # third-person shooter, retail US 1-disc CD as archive.org's
  # max-payne-2001-pc-game item preserves it (ISO9660, CID
  # QmY33VoGafwBpgMo75HrizwEF5ZzUy8Wm4ZDiD5LjEqZWZ). The tree is what the
  # disc's InstallShield 6 setup installs: the Program_Executable_Files
  # component of Disk1/data1.cab at the root (MaxPayne.exe, the four E2
  # engine MFC DLLs rlmfc/e2mfc/grphmfc/sndmfc, the bundled MFC42 /
  # MSVCRT / MSVCP60, x_data.ras / x_english.ras / x_music.ras, the
  # e2driver/ d3d8 renderer, help/, movies/, savegames/) plus the three
  # loose Disk1/Levels/x_level*.ras the setup copies in verbatim. The
  # InstallShield runtime components, the SafeDisc driver, the DirectX
  # redist and the level-editor installer are left out. Three files are
  # replaced over that:
  #
  #  - MaxPayne.exe: the v1.05 no-CD build (the final official patch
  #    with the SafeDisc IAT-encryption layer removed), from
  #    archive.org's "MP 1.05 crack.zip" on the same item (CID
  #    QmQYYbQ4WiLrTcJbFpSNEULnizgJcRjaPf7457JvU64CSs). Drops the
  #    disc/secdrv.sys dependency under Proton.
  #  - rlmfc.dll: the community-patched build for the JPEG/MMX crash on
  #    modern AMD/Intel CPUs (texture streaming dies with "JPEG header
  #    error" in the first chapter), verbatim from
  #    silentgameplays/Max-Payne-Fix-Windows-10 at d2ab8d9 ("FOR AMD
  #    CPUs Fix/", SHA1 d3db748214ed341dae49c172229d7eb332ab1fc9, the
  #    value the Steam Community guide cites). A different rlmfc build
  #    than retail v1.05 ships, but the engine's runtime ABI for it is
  #    stable and every major guide (PCGW, Steam Deck, ProtonDB) points
  #    at this file.
  #  - e2mfc.dll and e2driver/e2_d3d8_driver_mfc.dll: UCyborg's "Max
  #    Payne Series Startup Hang Patch" v1.01 (Jan 2017; PCGW community
  #    file 838, CID QmeGbpPiTMrU1VxWPdQJrkvij6YZypS4dtEqXUcW8hH1ET, the
  #    MP1 set). The MAX-FX engine initialises Direct3D inside DllMain
  #    with the loader lock held; DXVK-backed Proton d3d8 raced on the
  #    half-built device into a near-null write-AV ~100 ms after engine
  #    init. The patched DLLs defer D3D init until after LoadLibrary
  #    returns.
  src = fetchIpfs {
    cid = "bafybeiapk6qoytrl46e6db7r3o2nvkatemzgkw6f7qhfccth4w55ymreoq";
    bundle = true;
    hash = "sha256-CS1Kf+9QjWWmJXGkjHkJcx1xq4FhmTy9kozW/6hdwS8=";
    name = "max-payne";
    size = 596136065;
  };

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

  # On Android (GameNative, strom-3): DXVK's d3d8 under Box64 runs it to
  # the menu from a fresh container, measured on an AYN Thor.
  #
  # No -nodialog there. The screen mode lives only in the game's Display
  # Setup dialog (the in-game Video menu has sharpness and brightness),
  # and the dialog defaults to 640x480 in a corner of the panel. The
  # desktop seeds the registry from preRun instead; a phone cannot, so
  # the dialog stays: Play is focused when it opens, so it is one A press
  # per launch, and the mode is always one dialog away.
  android.containerConfig.execArgs = "-skipstartup";

  # The game reads keyboard and mouse only (DirectInput, no XInput), so
  # the pad is mapped to its defaults as its Controls screens list them:
  # W/A/S/D move, MB1 shoot, MB2 bullet time combo, space jump, C crouch,
  # E use / sniper zoom, R reload, Tab painkiller, mouse wheel weapons,
  # G best weapon, P pause.
  android.padKeys = {
    leftStick = "wasd";
    dpad = "wasd";
    rightStick = "mouse";
    r1 = "MOUSE_LEFT";
    l1 = "MOUSE_RIGHT";
    a = "SPACE";
    b = "C";
    x = "R";
    y = "E";
    r2 = "SCROLL_UP";
    l2 = "SCROLL_DOWN";
    r3 = "G";
    l3 = "TAB";
    start = "ESC";
    select = "P";
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
