{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Half-Life 2 (Valve, 2004, Source engine), the AnkerGames repack — the
  # same publisher and identical post-install tree layout as the repo's
  # working `games/portal`. A single RAR of an already-installed game,
  # rooted at `Half-Life 2/` (with a literal space): `Half-Life 2/hl2.exe`,
  # `Half-Life 2/bin/` (engine DLLs) and the `Half-Life 2/hl2/` game
  # directory, plus a baked-in Goldberg steam emu (root `Launcher.exe`
  # ColdClientLoader, `steamclient*.dll`, `steam_settings/` with appid 220).
  #
  # Unlike the previous "Retail build 2153" archive.org item — which shipped
  # ONLY bin/FileSystem_Steam.dll and was missing filesystem_stdio.dll, so
  # the game could not launch standalone OR via emu — this tree carries
  # bin/FileSystem_Stdio.dll (689 KB, verified present), the standalone
  # Source filesystem module. That makes the simplest, emu-free launch the
  # correct one: `hl2.exe -game hl2` with NO `-steam`, NO Goldberg loader.
  #
  # The RAR uses RAR5 method m5 which plain 7zz can list but not decompress;
  # `unar` (free, The Unarchiver — the repo convention for .rar, cf.
  # games/bioshock) handles it. No installer, no Steam depot — just `unar`
  # and launch hl2.exe under Proton.
  src = fetchIpfs {
    cid = "QmUZBT8TNRozqJpBqnCSv9Q971pFYBeMPDGM8pNHhkpSqT";
    hash = "sha256-SkO5Qa62OJBH4jGjCfZFRH5bCIVjuWXAcMXSEH11Fck=";
    name = "Half-Life-2-AnkerGames.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "half-life-2";

  inherit src;
  ipfsSources = [ src ];

  nativeBuildInputs = [ unar ];

  # Extract the RAR and hoist the `Half-Life 2/` root (note the space) up
  # to $out so the install dir is flat: $out/hl2.exe, $out/bin/, $out/hl2/.
  # Keeping the original spaced directory would force every path
  # (executable, copyGlobs, preRun) to quote a literal space — flat is
  # cleaner and matches dark-messiah / portal. `unar -D` extracts without
  # creating its own enclosing directory. The repack also ships a sibling
  # `Backup Cracks/` (alternate GBE Fork/RUNE/SKIDROW emu sets) and a
  # `Bonus/` dir we don't need; only the `Half-Life 2/` tree is copied out.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/x"
    unar -D -o "$TMPDIR/x" "$src" >/dev/null
    if [ -d "$TMPDIR/x/Half-Life 2" ]; then
      cp -a "$TMPDIR/x/Half-Life 2/." "$out/"
    else
      cp -a "$TMPDIR/x/." "$out/"
    fi
    chmod -R u+w "$out"
    test -f "$out/hl2.exe"
    test -f "$out/bin/FileSystem_Stdio.dll"
  '';

  runtime = "proton";
  executable = "hl2.exe";

  # Standalone (no `-steam`). The Source launcher picks its filesystem
  # module by this flag: with `-steam` it loads filesystem_steam.dll,
  # without it filesystem_stdio.dll. This tree ships bin/FileSystem_Stdio.dll
  # (and NO filesystem_steam.dll), so the no-`-steam` path is the correct
  # one for the filesystem module.
  #
  # NOTE: even without `-steam`, this AnkerGames build's bin/launcher.dll
  # and bin/steam_api.dll are Goldberg-instrumented and still drive the
  # Steam init path on startup, which resolves
  # `steamclient.dll!Steam_TerminateGameConnection`. Wine 10's builtin
  # lsteamclient proxy lacks that legacy Source entry point and aborts with
  # "unimplemented function lsteamclient.dll.Steam_TerminateGameConnection"
  # (verified 2026-06-21). The WINEDLLOVERRIDES below (same as games/portal)
  # force the repack's bundled Goldberg steamclient*.dll — which export the
  # full legacy ABI — and disable lsteamclient so the loader never rewrites
  # steamclient references to it. The Goldberg steamclient.dll /
  # steamclient64.dll sit at the game root next to hl2.exe, with
  # steam_settings/ (appid 220) alongside.
  #
  # `-game hl2` selects the single-player Half-Life 2 mod directory.
  #
  # NOTE: the original "crashes on the first changelevel (trainstation ->
  # d1_canals_01)" was NOT a renderer bug — `-vulkan` and dropping the
  # bundled bin/dxvk_d3d9.dll were both tried and neither helped. The real
  # cause is the save path: Source writes a transition save into hl2/SAVE/
  # next to the binary on every changelevel, and that dir sits on the
  # per-game fuse-overlayfs mount where Wine's case-insensitive lookup is
  # disabled (FUSE_SUPER_MAGIC), so the save fopen returns NULL and the
  # engine null-derefs mid-transition. The same fault is why manual saves
  # silently do nothing. preRun (below) redirects hl2/SAVE/ onto plain
  # btrfs ($STROM_GAMEDIR), exactly like games/gothic's Saves/ redirect.
  #
  # `-w 1920 -h 1080 -fullscreen` pin the Source video mode before the
  # engine reads cfg/video.txt, so a fresh prefix (the operator wipes the
  # wineprefix between tests) still comes up at the gamescope output size
  # instead of the engine's low first-launch fallback. Same approach as
  # games/dark-messiah-of-might-and-magic.
  executableArgs = [
    "-game"
    "hl2"
    "-w"
    "1920"
    "-h"
    "1080"
    "-fullscreen"
  ];

  saveLocations = [
    # Source 2004 writes savegames into hl2/SAVE/*.sav next to the binary,
    # NOT under drive_c/users/steamuser — so the generic saveLocations
    # relocation (which only pulls dirs out of drive_c) has nothing to do
    # here. The save persistence + the changelevel-crash fix both happen in
    # preRun, where hl2/SAVE/ is symlinked off the fuse-overlayfs mount onto
    # plain btrfs ($STROM_GAMEDIR/.saves-real); that target also survives
    # prefix wipes, exactly like a saveLocations entry would.
  ];

  # Save redirect — the actual fix for both "saves do nothing" and the
  # changelevel crash. hl2/SAVE/ lives next to the binary on the per-game
  # fuse-overlayfs merged mount, where ntdll's get_dir_case_sensitivity()
  # disables Wine's case-insensitive directory scan (no .ciopfs marker on a
  # FUSE mount). The Source save path then can't resolve its mixed-case
  # SAVE\ dir, the fopen returns NULL, and the engine null-derefs the
  # instant it writes a save — including the transition save Source does on
  # every changelevel. $STROM_GAMEDIR (the overlay's writable upper) is ALSO
  # bind-mounted into the sandbox at its own path as plain btrfs, separate
  # from the merged FUSE mount at $GAMEDIR. We make a real save dir there
  # and symlink hl2/SAVE -> it, so Wine follows the link to btrfs, keeps the
  # case-insensitive scan on, and the save completes (and persists across
  # prefix wipes). Canonical pattern: games/gothic's Saves/ redirect.
  #
  # We create the symlink directly on $STROM_GAMEDIR (the overlay's plain
  # btrfs upper) rather than through the merged FUSE mount at $GAMEDIR:
  # `ln`/rename onto fuse-overlayfs returns EXDEV ("Invalid cross-device
  # link") when the parent (hl2/, a read-only lower dir) must be copied up
  # first (cf. reference_fuse_overlayfs_sed_i_exdev — unlike gothic's
  # root-level Saves/, hl2/SAVE is one level deep). A symlink written into
  # the upper's hl2/ dir merges into the view as $GAMEDIR/hl2/SAVE all the
  # same, with no copy-up dance.
  preRun = ''
    STROM_SAVES_REAL="$STROM_GAMEDIR/.saves-real"
    mkdir -p "$STROM_SAVES_REAL" "$STROM_GAMEDIR/hl2"
    # Replace any stale real hl2/SAVE dir from an older run with the symlink
    # to btrfs; a real dir would keep the engine on the FUSE path.
    if [ -e "$STROM_GAMEDIR/hl2/SAVE" ] && [ ! -L "$STROM_GAMEDIR/hl2/SAVE" ]; then
      cp -an "$STROM_GAMEDIR/hl2/SAVE/." "$STROM_SAVES_REAL/" 2>/dev/null || true
      rm -rf "$STROM_GAMEDIR/hl2/SAVE"
    fi
    ln -snf "$STROM_SAVES_REAL" "$STROM_GAMEDIR/hl2/SAVE"
  '';

  env = {
    # Source 2004 is 32-bit; large-address-aware lifts the 2 GiB virtual
    # address ceiling on the heavier maps (same as dark-messiah).
    WINE_LARGE_ADDRESS_AWARE = "1";
    # Half-Life 2 Steam AppID, in case the engine probes it.
    STEAM_COMPAT_APP_ID = "220";
    SteamAppId = "220";
    SteamGameId = "220";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    # Force native (bundled Goldberg) steam_api.dll and steamclient*.dll
    # over Wine's builtin lsteamclient.dll proxy, which is missing legacy
    # Source entry points like Steam_TerminateGameConnection and aborts.
    # Same bypass as games/portal / games/portal-2.
    WINEDLLOVERRIDES = "steam_api,steamclient,steamclient64=n,b;lsteamclient=";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
    # Pin US qwerty inside gamescope's nested Xwayland so the Source
    # engine's first-run keybind autoconfig writes WASD, independent of
    # the host xkb layout (ValveSoftware/gamescope#203 workaround, same
    # as dark-messiah).
    env = {
      XKB_DEFAULT_LAYOUT = "us";
      XKB_DEFAULT_VARIANT = "";
    };
  };

  meta = {
    description = "Half-Life 2 (Valve 2004, Source engine, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "half-life-2";
  };
}
