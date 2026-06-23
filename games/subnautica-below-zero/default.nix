{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Subnautica: Below Zero (Unknown Worlds Entertainment, 2021) — standalone
  # follow-up to Subnautica, an underwater survival/adventure built on Unity.
  # ProtonDB Platinum (runs out of the box, no tweaks), so runtime = "proton".
  # Not on GOG; sourced from a SteamRIP pre-installed/pre-cracked build that
  # ships a bundled Steam emulator so it runs fully offline (no steam_api
  # swap needed).
  #
  # SOURCE: SteamRIP "Subnautica: Below Zero" v49636 (Full/Latest), a
  # single-file RAR5 archive (5,680,503,346 bytes). The archive root holds
  # the game tree under a "Subnautica Below Zero/" folder plus SteamRIP junk
  # (_CommonRedist/, Read_Me_Instructions.txt, a .url shortcut) that we drop.
  # Inside "Subnautica Below Zero/" is the flat Unity layout:
  # SubnauticaZero.exe + SubnauticaZero_Data/ + UnityPlayer.dll, with a
  # CODEX/SteamRIP steam_api64.dll + steam_emu.ini emulator already in place
  # so it runs fully offline.
  src = fetchIpfs {
    cid = "Qmf4ynWQ5huycLzWpeoB7dfu2CLwBSj3d3VWkAcSref7fd";
    fallbackUrl = "https://archive.org/download/subnautica-below-zero-steam-rip.com/Subnautica-Below-Zero-SteamRIP.com.rar";
    hash = "sha256-Aw1hB1ML0AcAXwrN0PDh/lr6PQ1+Wmd54zV/mZ1THjM=";
    name = "subnautica-below-zero-steamrip-v49636.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "subnautica-below-zero";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"
    unar -force-overwrite -no-directory -output-directory "$TMPDIR/extract" "$src"
    cp -a "$TMPDIR/extract/Subnautica Below Zero"/. "$out"/
    # Drop the SteamRIP redistributable installers and shortcuts; the strom
    # wrapper execs the exe under Proton directly.
    rm -rf "$out/_CommonRedist"
    rm -f "$out/Read_Me_Instructions.txt" "$out"/*.url
    # 32-bit launcher stub is unused; we run the 64-bit SubnauticaZero.exe.
    rm -f "$out/Subnautica32.exe"
    # Drop the Unity crash reporter: `proton waitforexitandrun` waits for
    # every wine process to exit, so a lingering UnityCrashHandler wedges
    # proton/gamescope open after a clean quit (cf. chants-of-sennaar).
    rm -f "$out/UnityCrashHandler32.exe" "$out/UnityCrashHandler64.exe"
    # The build ships SNAppData/ holding two empty save dirs (SavedGames +
    # SavedGamesBackup) and nothing else. Drop the WHOLE SNAppData/ tree here so
    # it does not reach the read-only fuse-overlayfs lower at all: a save write
    # inside a lower-only dir forces an overlay copy-up whose rename crosses
    # devices -> EXDEV. With SNAppData/ absent from the lower, preRun recreates
    # it (as symlinks onto plain btrfs) in the overlay's writable upper. See the
    # saveLocations/preRun comments below.
    rm -rf "$out/SNAppData"
  '';

  runtime = "proton";
  executable = "SubnauticaZero.exe";

  # Run Unity FULLSCREEN at exactly the gamescope nest resolution (1920x1080,
  # matched to gamescope.{output,nested}-{width,height} below). The menu cursor
  # bug is a RESOLUTION-MISMATCH bug, not a gamescope-vs-no-gamescope one: the
  # Subnautica Unity engine draws an absolute SOFTWARE cursor for menus whose
  # screen-space mapping breaks whenever the game's render resolution is smaller
  # than the surface/monitor it's composited onto -- the cursor then parks at
  # the surface center and won't track (confirmed upstream: the menu cursor
  # "only happens when the game resolution is lower than my monitor resolution",
  # fixed by matching the two; ValveSoftware/Proton#1337, Steam BZ bug threads).
  # So the cure is to make Unity's internal resolution EQUAL the surface it
  # renders into. Inside the nest gamescope IS that surface, so fullscreen at
  # the nest's 1920x1080 leaves no mismatch and the absolute cursor tracks.
  # (Same recipe as the working Unity/Proton menu cursors in chants-of-sennaar,
  # deep-rock-galactic-survivor, graveyard-keeper, broforce.)
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  # The engine does NOT save into AppData/LocalLow -- that LocalLow tree only
  # ever holds Player.log. Subnautica: Below Zero writes its savegames into a
  # binary-adjacent SNAppData/SavedGames/ tree NEXT TO SubnauticaZero.exe (one
  # subdir per slot: slot0000/, ...), plus a SNAppData/SavedGamesBackup/. The
  # save redirect in preRun (below) keeps these off the fuse-overlayfs mount on
  # plain btrfs; with the actual saves handled there, the generic saveLocations
  # relocation has nothing to do.
  saveLocations = [ ];

  # Save redirect: keep the binary-adjacent SNAppData/ save tree OFF the
  # fuse-overlayfs mount and on plain btrfs so the engine can actually create
  # save slots.
  #
  # The engine enumerates saves at startup and, on mode-select, calls
  # UserStoragePC.SaveFilesAsyncImpl -> Directory.CreateDirectory to write a
  # slot under binary-adjacent SNAppData/SavedGames/. Its .NET save path does an
  # atomic write-temp-then-rename(2). On the fuse-overlayfs merged game mount
  # (Wine's Z: -> /tmp/.strom-overlay) that rename crosses the overlay<->btrfs
  # boundary and returns EXDEV, surfaced as IOException "Source and destination
  # are not on the same device" -- which both blocks new-game start AND pops a
  # "Save data loading failed" modal at the main menu. Merely pre-creating the
  # dirs in the upper does NOT help: the engine still reaches them through the
  # FUSE mount, where rename is fundamentally cross-device.
  #
  # Fix (the canonical binary-adjacent-saves-on-FUSE redirect, cf. gothic +
  # reference_fuse_overlayfs_sed_i_exdev): keep the save tree OFF the overlay
  # entirely. buildScript drops the shipped SNAppData/ so it is absent from the
  # read-only lower. Here we make the real save dirs on plain btrfs at
  # $STROM_GAMEDIR/.snappdata/<name>, then place SYMLINKS to them in
  # $STROM_GAMEDIR/SNAppData/<name> -- i.e. written straight into the overlay's
  # upperdir ($STROM_GAMEDIR), never into the merged $GAMEDIR root (which would
  # trigger an EXDEV copy-up of the lower-only overlay root in-namespace and
  # block launch in preRun). The symlinks then show up in the merge at
  # $GAMEDIR/SNAppData/<name>; when Wine follows them it lands on the
  # $STROM_GAMEDIR btrfs path (bind-mounted into the ns at its own location),
  # which is NOT under the FUSE mount -- so the engine's rename stays on one
  # device and the save completes. The targets live in $STROM_GAMEDIR, so saves
  # also persist across prefix/overlay wipes.
  preRun = ''
    for __sn_d in SavedGames SavedGamesBackup; do
      mkdir -p "$STROM_GAMEDIR/.snappdata/$__sn_d" "$STROM_GAMEDIR/SNAppData"
      ln -snf "$STROM_GAMEDIR/.snappdata/$__sn_d" "$STROM_GAMEDIR/SNAppData/$__sn_d"
    done
  '';

  # Nest in gamescope. This gives exactly ONE seat-managed Xwayland toplevel
  # (so the window appears in the WM tree, alt-tabs, and never grabs the whole
  # workspace the way Unity's own exclusive-fullscreen does), AND -- with the
  # nest sized 1:1 to the game's render resolution (executableArgs above) -- a
  # working absolute MENU cursor. The earlier no-gamescope attempts failed both
  # ways: default fullscreen took exclusive fullscreen and locked the seat, and
  # a smaller windowed mode (1600x900 on a 2880x1920 seat) opened an
  # override-redirect overlay the WM couldn't manage AND re-triggered the
  # resolution-mismatch cursor bug. The earlier in-nest cursor failures were a
  # SIZING bug, not a fundamental gamescope incompatibility: with no
  # output/nested size set, gamescope's surface didn't match Unity's internal
  # resolution and the software cursor parked at center; `--force-grab-cursor`
  # then forced relative mode and drew no menu cursor at all (gamescope#707).
  # Matching all four sizes to 1920x1080 and letting Unity fullscreen at the
  # same size removes the mismatch (cf. chants-of-sennaar). gamescope upscales
  # the 1920x1080 surface -- cursor included, in lockstep -- onto the real seat.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Subnautica: Below Zero (Unknown Worlds 2021, Unity underwater survival via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "subnautica-below-zero";
  };
}
