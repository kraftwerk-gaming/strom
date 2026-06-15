{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  libarchive,
  p7zip,
  python3,
}:

let
  # Unrailed! (Indoor Astronaut / Daedalic, 2020). Chaotic co-op
  # train-track-building game on the FNA (XNA reimplementation) runtime, a
  # 64-bit Mono/.NET assembly (UnrailedGame.exe). A native Linux build exists
  # but ships only as a Steam-DRM depot (no DRM-free Linux source), so we run
  # the Windows build under Proton.
  #
  # SOURCE: the IGG-GAMES "Unrailed.v2025.07.17" pre-installed repack (single
  # RAR5, apibay/PCGAMESTORRENTS magnet). The repack is already cracked with
  # gbe_fork (steam_settings/ + steam_appid.txt for AppId 1016920, and the
  # original 64-bit steam_api.dll backed up as steam_api.dll.bak), so the game
  # starts offline without a Steam client. p7zip 17.05 can't decode this
  # archive ("Unsupported Method" on RAR5) and unrar is unfree, so bsdtar
  # (libarchive) is the in-sandbox extractor.
  src = fetchIpfs {
    cid = "QmT6Wj96bGUg57FJM3hU7PZ4MV9MMw8btDNwuWKtBPb7Mo";
    fallbackUrl = "magnet:?xt=urn:btih:2B5AD9433CD2DB54393AFA439A471C6C9153CB27";
    hash = "sha256-TWb4wZW67ZHKDd2ZaOrsKkbujVEWM17MBzaI964rFFE=";
    name = "Unrailed.v2025.07.17.rar";
  };

  # The repack's bundled gbe_fork steam_api.dll is the 32-bit (PE32) build,
  # but UnrailedGame.exe is 64-bit and loads the 64-bit steam_api.dll -- a
  # 64-bit process can't load a 32-bit DLL, so SteamAPI_Init faults at
  # startup. Swap in the matching 64-bit gbe_fork steam_api64.dll under the
  # filename the game actually loads (steam_api.dll, the name of the original
  # backed-up retail DLL). The repack's steam_settings/ + steam_interfaces.txt
  # (SteamClient017/018 / SteamUser020 / ...) already match the game's SDK.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "unrailed";

  inherit src;
  ipfsSources = [ src ];

  nativeBuildInputs = [
    libarchive
    p7zip
    python3
  ];

  buildScript = ''
    mkdir -p "$out"
    # bsdtar (libarchive) reads the RAR5 container; some Content/ filenames
    # carry non-ASCII bytes the sandbox C locale can't decode, so bsdtar warns
    # and exits non-zero while the full game/ tree still extracts -- tolerate it.
    bsdtar -xf "$src" -C "$TMPDIR" || true
    cp -a "$TMPDIR/Unrailed.v2025.07.17/game/." "$out"/
    chmod -R u+w "$out"

    # Drop the Steam emulator's leftover backup of the original DLL. (The
    # repack's marketing .url shortcuts live at the archive root, outside the
    # game/ tree we copy, so they never reach $out.)
    rm -f "$out/windows/steam_api.dll.bak"

    # Replace the wrong-arch (32-bit) gbe_fork DLL with the 64-bit one.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$out/windows/steam_api.dll"

    # UnrailedGame.exe (AnyCPU, runs 64-bit) references types from
    # UnrailedCrashDumper.exe, which is built AnyCPU-prefer-32 (CorFlags
    # 0x20003). wine-mono 10.x mishandles the 32BITPREFERRED flag and rejects
    # it as 32-bit-only, so the main exe's early CertManager reference throws
    # TypeLoadException before the menu. Strip the 32-bit CorFlags to leave a
    # pure ILONLY image that loads into the 64-bit host.
    python3 ${./clear-32bit-flag.py} "$out/UnrailedCrashDumper.exe"
  '';

  runtime = "proton";
  executable = "UnrailedGame.exe";

  env = {
    SteamAppId = "1016920";
    SteamGameId = "1016920";
    # Load the gbe_fork Steamworks emu DLL native, never Wine's builtin stub.
    WINEDLLOVERRIDES = "steam_api=n,b";
  };

  # FNA persists local config/replays via SDL_GetPrefPath under
  # AppData/Roaming/Unrailed; gbe_fork mirrors Steam Cloud progress into
  # AppData/Roaming/GSE Saves/1016920/. Relocate both so a prefix wipe keeps
  # settings and co-op progress.
  saveLocations = [
    "AppData/Roaming/Unrailed"
    "AppData/Roaming/GSE Saves"
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

  meta = {
    description = "Unrailed! (Indoor Astronaut / Daedalic 2020, FNA co-op track-builder, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "unrailed";
  };
}
