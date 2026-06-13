{
  self,
  lib,
  pkgs,
  fetchIpfs,
  libarchive,
}:

let
  # Ostranauts (Blue Bottle Games, 2024) -- spaceship-derelict survival
  # sim from the NEO Scavenger developer. Unity 2021 Mono build. No
  # native Linux build ships in this release, so runtime = "proton".
  # IGG/PCGamesTorrents repack of the v2026.05.13 Windows build, a RAR5
  # archive with the game tree at Ostranauts.v2026.05.13/game/
  # (Ostranauts.exe + Ostranauts_Data/ + UnityPlayer.dll). The repack
  # already swaps in a Goldberg-style steam_api64.dll (the original is
  # kept as steam_api64.dll.bak) with steam_settings/steam_appid.txt =
  # 1022980, so it boots offline with no Steam client / login.
  src = fetchIpfs {
    cid = "QmbTCFt7zsSkTvjo7aar6VRczPALPYXY36ovdu4UAJaFSx";
    fallbackUrl = "";
    hash = "sha256-O+MR6yAx4VbbvnwmdFQrQXM0IQL+t020CnLYHjjx1K0=";
    name = "ostranauts-v2026.05.13.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "ostranauts";

  ipfsSources = [ src ];
  inherit src;

  # bsdtar (libarchive) reads the RAR5 container; nixpkgs' unrar is
  # unfree, and p7zip 17.05 can't open RAR5, so libarchive is the only
  # free in-sandbox extractor here.
  nativeBuildInputs = [ libarchive ];

  buildScript = ''
    mkdir -p "$out"
    # Some repack shortcut entries (*.url) carry UTF-16BE filenames the
    # sandbox's C locale can't decode; bsdtar skips them and exits
    # non-zero, but the whole game/ tree extracts fine, so tolerate it.
    bsdtar -xf "$src" -C "$TMPDIR" || true
    cp -a "$TMPDIR/Ostranauts.v2026.05.13/game/." "$out"/
    # Drop the repack's marketing shortcuts and the Steam emulator's
    # leftover backup of the original DLL.
    rm -f "$out"/*.url "$out"/steam_appid.txt
    # Ostranauts.exe spawns UnityCrashHandler64.exe to monitor it. On a
    # clean quit the main process exits but the crash handler can linger;
    # `proton waitforexitandrun` waits for *every* wine process to exit,
    # so a surviving handler wedges proton open and gamescope never tears
    # down. Unity runs fine without it, so drop it for a clean exit.
    rm -f "$out/UnityCrashHandler64.exe"
  '';

  runtime = "proton";
  executable = "Ostranauts.exe";

  # Unity LocalLow tree; saves live under Saves/, settings alongside.
  saveLocations = [ "AppData/LocalLow/Blue Bottle Games/Ostranauts" ];

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

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

  meta = {
    description = "Ostranauts (Blue Bottle Games 2024, Unity spaceship-survival sim, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "ostranauts";
  };
}
