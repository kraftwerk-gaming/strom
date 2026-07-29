{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG Windows release of Homeworld Remastered Collection v2.1 (build
  # 3877). Three-part GOG installer (.exe + 2 .bin slices). innoextract
  # reads them together when they sit next to each other; we symlink
  # them in $TMPDIR with the original filenames before extracting.
  #
  # Same three CIDs as `games/homeworld` and `games/homeworld-2`, which
  # ship the two classic engines out of this same installer. One pin
  # covers all three packages; nothing new needed uploading.
  setupExe = fetchIpfs {
    cid = "QmNZii5dEietiWJ3XWamoXtZVJ4G8uWoMokCFXjg38puiQ";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29.exe";
    hash = "sha256-G5xedp7ALYkNvhfF0hU1UnTGxwwxflBAlgFTZo7Cijs=";
    name = "homeworld-remastered-gog-2.1.exe";
  };

  setupBin1 = fetchIpfs {
    cid = "QmcAz3HugvgxsXrqUjSpoz2pKDQKiMi9bee8fbKDcz9nV4";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29-1.bin";
    hash = "sha256-V82oiqkkQGMPEv1iohZ0d2ZiwK7PvUWKzkqU/m04aHM=";
    name = "homeworld-remastered-gog-2.1-1.bin";
  };

  setupBin2 = fetchIpfs {
    cid = "QmWNTi4bwTDXjQRmsu2ua4z6nvPvYBK5kEBPWWyC8RxPYy";
    fallbackUrl = "https://archive.org/download/homeworld-remastered-collection-gog/Homeworld%20Remastered%20Collection%20%5BGOG%5D/setup_homeworld_remastered_2.1_%283877%29-2.bin";
    hash = "sha256-CjcrK21uVNwbC0Pz8/JNsviaSHwNKKfh9zt6JFd9XyQ=";
    name = "homeworld-remastered-gog-2.1-2.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "homeworld-remastered";

  ipfsSources = [
    setupExe
    setupBin1
    setupBin2
  ];

  src = setupExe;

  nativeBuildInputs = [ innoextract ];

  # `-I app/HomeworldRM` keeps only the 2015 Gearbox remaster (~6.5 GiB)
  # out of the ~8.3 GiB collection. Homeworld1Classic is shipped by
  # `games/homeworld` and Homeworld2Classic by `games/homeworld-2`;
  # HWLauncher is the .NET/WPF picker GUI, which this package replaces
  # by launching HomeworldRM.exe directly.
  #
  # The tree is shipped BYTE FOR BYTE as GOG built it. No patched exe,
  # no substituted DLL, nothing to audit. See the Galaxy note below --
  # an earlier attempt shipped a hand-rolled Galaxy.dll and a branch
  # patch, and neither turned out to be necessary.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/hw"
    ln -s ${setupExe}  "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    ln -s ${setupBin1} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-1.bin"
    ln -s ${setupBin2} "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877)-2.bin"
    innoextract --gog -I app/HomeworldRM -d "$TMPDIR/iss" \
      "$TMPDIR/hw/setup_homeworld_remastered_2.1_(3877).exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
  '';

  runtime = "proton";

  # HomeworldRM.exe is PE32 i386 (COFF machine 0x14c, optional header
  # magic 0x10b) -- which is also why GOG ships the SDK here as
  # Galaxy.dll and not Galaxy64.dll. It renders through OPENGL32 and
  # plays through DSOUND; it imports no d3d9 and no ddraw at all.
  executable = "HomeworldRM/Bin/Release/HomeworldRM.exe";

  # THE GALAXY.DLL "BLOCKER" WAS NOT THE BLOCKER. Recorded here because
  # the wrong diagnosis was carried in `games/homeworld`'s header for a
  # while and cost an earlier attempt a hand-rolled SDK stub plus a
  # patched exe, neither of which this package needs.
  #
  # What is true: HomeworldRM.exe binds Galaxy.dll from its STATIC
  # import directory (IMAGE_DIRECTORY_ENTRY_IMPORT; the delay-import
  # directory is empty), so the DLL must resolve at load or the image
  # fails with c0000135. It imports exactly four MSVC-mangled
  # GalaxyFactory statics:
  #   ?GetInstance@GalaxyFactory@api@galaxy@@SAPAVIGalaxy@23@XZ
  #   ?CreateInstance@GalaxyFactory@api@galaxy@@SAPAVIGalaxy@23@XZ
  #   ?ResetInstance@GalaxyFactory@api@galaxy@@SAXXZ
  #   ?GetErrorManager@GalaxyFactory@api@galaxy@@SAPAVIErrorManager@23@XZ
  # reached through the inline GalaxyApi.h wrappers MSVC emitted as
  # COMDATs at 0x4bd9e5 (api::Init -> CreateInstance()->vtbl[1](clientID
  # "48201844549712537", secret, throwExceptions=0)) and 0x4bda77
  # (api::GetError -> GetErrorManager()->vtbl[1]()). The engine's
  # GalaxyPeer::Init at 0x4bdc5d stores "GetLastError() == NULL" into
  # g_galaxyInit (0x9e9091); the other 50 references to that global are
  # all gates, so a false value cleanly disables the whole Galaxy layer.
  #
  # Also true: with no Galaxy client running the shipped SDK really does
  # throw. A +seh trace shows 16 e06d7363 (EXCEPTION_WINE_CXX_EXCEPTION)
  # and Galaxy.dll's own SEH descriptors registering catch types
  # .?AVIRuntimeError@api@galaxy@@, IUnauthorizedAccessError,
  # IInvalidArgumentError, IInvalidStateError.
  #
  # What is FALSE is that any of that is fatal. Galaxy.dll catches its
  # own throw, GalaxyPeer::Init takes the offline branch, and the game
  # keeps going. Measured on this tree, stock DLL, nothing modified:
  # 121 s of continuous rendering ending only because the test harness
  # timed out -- 24 frames, HomeworldRM.exe alive throughout, the
  # remastered CREATE NEW PROFILE dialog on screen. There is no ~10 s
  # teardown.
  #
  # What actually produces a silent early exit is the engine failing to
  # write next to its own binary. HomeworldRM does the same write.txt
  # permission probe as the HW2 classic engine, plus HwRM.log and
  # ..\profiles\. Measured with one variable changed -- identical exe,
  # identical stock Galaxy.dll, cwd pointed at the read-only /nix/store
  # copy of the same tree instead of the writable overlay (a `touch`
  # from preRun confirmed the directory rejects file creation): the
  # process died in about 5 s, zero frames, no window, exit status 0.
  # That is exactly the recorded symptom.
  #
  # [INFERENCE, not reproduced] The earlier attempt (branch
  # patches/homeworld-remastered, de67fdf, 2026-05-08) was based before
  # 73e3ae6 "mk-game: fix overlay copy-up EXDEV (games can't write next
  # to binary)" of 2026-07-17 -- `git merge-base --is-ancestor 73e3ae6
  # patches/homeworld-remastered` returns false. On that base the
  # write.txt copy-up failed EXDEV, which is the same class of failure
  # the read-only-cwd run reproduces here. Confirming it exactly would
  # mean rebuilding the pre-fix base, which nobody needs.
  #
  # If a future Proton or Galaxy change ever does make the SDK fatal,
  # the shim work is not lost: a verified no-op Galaxy.dll (four
  # matching mangled exports, MSVC vtable slot numbering, gcc thiscall
  # emitting `ret 0xc` for Init and `ret 8` for Register/Unregister,
  # GetLastError returning non-NULL so g_galaxyInit stays false) is
  # recorded in this branch's commit message.

  # Everything the engine owns lives inside the install tree, so the
  # per-game fuse-overlayfs upper already persists it and there is
  # nothing under drive_c/users/steamuser to list.
  #
  # Verified empirically after runs that reached the remastered main
  # menu. `find ~/.strom/.compatdata/homeworld-remastered-collection/0/
  # pfx/drive_c/users/steamuser -type f` returns ZERO files, and the
  # only directories present are the wineprefix skeleton plus
  # AppData/{Local,Roaming}/Microsoft and AppData/Local/Temp -- no
  # Documents/My Games, no AppData/LocalLow/<vendor>, nothing the 2015
  # Gearbox rewrite added. Meanwhile the overlay upper gained
  # LOGFILES/ SCREENSHOTS/ CACHE/ STATS/ SYNCERROR/ PATCH/ GAMERULES/
  # Profiles/ under HomeworldRM/Bin/, plus
  # HomeworldRM/Bin/Release/{HwRM.log,write.txt}. Profiles/ is where
  # savegames go (Profiles/<name>/Campaign/<CAMPAIGN>/*.sav), and
  # "GAME -- Using player profile <name>" in HwRM.log confirms the
  # engine reads them back from there.
  saveLocations = [ ];

  preRun = ''
    # The engine builds its filepath aliases off the PROCESS WORKING
    # DIRECTORY: "executable" -> ".\", "bin" -> "..\", "updates" ->
    # "..\..\DataUpdates\", "workshop" -> "..\..\DataWorkshopMODs\",
    # and the log/cache/stats/screenshot/profile dirs off "..\" (alias
    # table at .rdata 0x8dbd3c..0x8dbd94). Only Bin/Release makes those
    # walks land inside the install. It is also the directory holding
    # seDXAudio.dll / seFDAudio.dll, which the sound layer discovers by
    # globbing se*.dll in the cwd -- the exact trap that silently killed
    # audio in games/homeworld-2. Move this cd and both break.
    cd "$GAMEDIR/HomeworldRM/Bin/Release"
  '';

  # CAMPAIGN SELECTION. The collection holds two remastered campaigns
  # and the engine can only hold one per launch: the campaign identity
  # is a single scalar the engine derives from argv (0x407546 compares
  # the -moviepath token against "DataHW1Campaign" -> 1 and
  # "DataHW2Campaign" -> 2; 0x4070dd does the same for -dlccampaign
  # against "HW1Campaign.big" / "HW2Campaign.big"). Gearbox's answer was
  # HWLauncher.exe, a .NET/WPF picker that just re-runs the exe with one
  # of two argv sets; those two command lines, recovered verbatim from
  # Launcher.exe's UTF-16 string pool, are the ones below.
  #
  # Measured, all three headless: with NO campaign argv the main menu
  # comes up branded "HOMEWORLD REMASTERED" but has NO campaign entry at
  # all (TUTORIAL / EXTRA MISSIONS / PLAYER VS CPU / MULTIPLAYER /
  # PLAYER PROFILES / OPTIONS / MOVIES), so shipping no flag would hide
  # the game's main content. With the HW1 set the whole front end
  # reskins to Homeworld 1 Remastered (Kharak) and gains SINGLE PLAYER
  # GAME; with the HW2 set it reskins to "HOMEWORLD 2 REMASTERED"
  # (Hiigara) and likewise gains SINGLE PLAYER GAME. There is no
  # in-engine switch between them.
  #
  # So we default to Homeworld 1 Remastered, the campaign the collection
  # is named for and the first one the Gearbox launcher lists. Homeworld
  # 2 Remastered is one override away (AGENTS.md "Customizing a game");
  # this exact argv was run and reached its main menu:
  #
  #   (strom.modules.x86_64-linux.homeworld-remastered-collection.apply {
  #     executableArgs = lib.mkForce [
  #       "-dlccampaign" "HW2Campaign.big"
  #       "-campaign" "Ascension"
  #       "-moviepath" "DataHW2Campaign"
  #     ];
  #   }).outputs.wrapper
  #
  # Appending the HW2 flags to `nix run .#... --` does NOT work and is
  # not a documented path: the wrapper puts executableArgs before "$@",
  # and the engine's option lookup (0x7a97a2) walks the token vector
  # from index 0 and returns the FIRST match, so the defaults below win.
  executableArgs = [
    "-dlccampaign"
    "HW1Campaign.big"
    "-campaign"
    "HomeworldClassic"
    "-moviepath"
    "DataHW1Campaign"
  ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  env = {
    # Deliberately NO MESA_GL_VERSION_OVERRIDE. Both classic siblings
    # set 3.3COMPAT, and it looked like it should be inherited, but it
    # is not needed here and carrying it would be cargo cult. A/B'd on
    # this hardware: with the override HwRM.log says "GL Info: 3.3 - 3.3
    # (Compatibility Profile) Mesa 26.1.5"; with the variable unset it
    # says "GL Info: 4.6 - 4.6 (Compatibility Profile) Mesa 26.1.5" and
    # the game reaches exactly the same main menu. radeonsi hands out a
    # COMPATIBILITY profile by default, which is what the engine's probe
    # actually wants, so there is nothing to override.
    #
    # HomeworldRM.exe does NOT carry IMAGE_FILE_LARGE_ADDRESS_AWARE
    # (COFF characteristics 0x0102), so without this it is capped at a
    # 2 GiB user address space while streaming a 6.5 GiB asset set.
    WINE_LARGE_ADDRESS_AWARE = "1";
    LANG = "en_US.UTF-8";
  };

  meta = {
    description = "Homeworld Remastered Collection (Gearbox/Relic, 2015 remasters of Homeworld and Homeworld 2, GOG v2.1 build 3877, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "homeworld-remastered";
  };
}
