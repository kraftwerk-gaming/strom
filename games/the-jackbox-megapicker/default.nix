{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  p7zip,
}:

let
  # SCOPE DECISION (the-jackbox-megapicker request, rad issue 4da645a):
  # "The Jackbox Megapicker" (Steam app 2828500) is an official but
  # *contentless* launcher - it only scans your Steam library for already-
  # installed Jackbox Party Packs and lets you pick a game across them.
  # Packaged on its own it shows an empty library, so it is useless as a
  # standalone target. The issue itself notes it "bundles multiple Jackbox
  # party packs; may not all install/run together". The actionable
  # deliverable is therefore a single Party Pack, launched directly (the
  # Megapicker's only role is a `jackbox://` protocol handoff via
  # launch_mp.bat, which we bypass by launching the pack exe directly).
  #
  # Pack 7 was chosen: it is Platinum-rated on ProtonDB, is one of the two
  # universally top-ranked packs, and is the only top pack with a verified,
  # direct, non-Cloudflare archive.org PC ZIP at a manageable ~1.66 GB.
  #
  # The build is a plain extracted Steam build of a native Scaleform GFx app
  # (TJPPLoader.swf + .swf game modules under games/, played by the engine
  # baked into the exe; FMOD audio, CRIWARE Sofdec2 .usm intro). It is NOT
  # SteamStub-wrapped (no .bind/.stub section), so the exe launches
  # standalone. Players join the room from a browser at jackbox.tv; the game
  # window only shows the host UI / room code.
  #
  # ROOT-CAUSE FIX (user symptom "not doing anything on start"): the bundled
  # steam_api64.dll is the RETAIL Valve SDK DLL (296 KB), not a no-op stub.
  # At launch its SteamAPI_Init() tries to LoadModule
  # "C:\Program Files (x86)\Steam\steamclient64.dll", fails with no running
  # Steam, and returns false. The game does not null-check: the Proton log
  # shows "[S_API] SteamAPI_Init(): Sys_LoadModule failed to load:
  # ...steamclient64.dll" / "ERROR: Failed to initialize Steam" immediately
  # followed by an EXCEPTION_ACCESS_VIOLATION at exe+0x20B449 (rcx=0). The
  # faulting code is `mov rcx,[rax]` (load cached ISteam* ptr, left NULL) /
  # `mov r9,[rcx]` (load its vtable) then `call [r9+0xD0]` — an unchecked
  # call through the NULL Steam interface. Swap in gbe_fork (Goldberg fork)
  # so SteamAPI_Init succeeds offline and serves real interface objects.
  src = fetchIpfs {
    cid = "QmTuc6xHziHS2JUQDwh9xdrwEgzeMpwQw4GkGcZ7C9eXnj";
    fallbackUrl = "https://archive.org/download/the-jackbox-party-pack-7/The%20Jackbox%20Party%20Pack%207.zip";
    hash = "sha256-rGkQWeu726YUhQ7pB6aXBh0+GVwCPNQUfFd8Cm4B4q4=";
    name = "the-jackbox-megapicker.zip";
  };

  # gbe_fork: drop-in steam_api64.dll that fakes SteamAPI_Init + interfaces
  # offline. The `regular` x64 build is enough here — the game only needs
  # init to succeed and basic ISteamUser/ISteamApps/ISteamUtils, not
  # SteamInput (no action sets in the exe; players join from a browser).
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_05_19/emu-win-release.7z";
    hash = "sha256-e+Dq0x+y1HdHzEwmmi4vbBmtOTsji/erVhSZRPyK9bs=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-jackbox-megapicker";

  inherit src;

  nativeBuildInputs = [
    unzip
    p7zip
  ];

  # The zip wraps a single top-level dir ("The Jackbox Party Pack 7/").
  # Strip it so the exe sits at $out root. The exe name contains spaces.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/The Jackbox Party Pack 7/." "$out"/
    chmod -R u+w "$out"
    test -f "$out/The Jackbox Party Pack 7.exe" \
      || { echo "main exe missing from extracted tree" >&2; exit 1; }

    # Replace the retail Valve steam_api64.dll with gbe_fork so
    # SteamAPI_Init() succeeds offline (see src comment for the crash this
    # fixes). The game resolves steam_api64.dll from the exe dir.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    install -m0644 "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$out/steam_api64.dll"

    # gbe_fork reads steam_settings/ next to its DLL, and the SDK also
    # honours a steam_appid.txt beside the exe; report Pack 7 (1211630,
    # gameManifest.json steam.appId) as owned so init resolves consistently.
    echo -n 1211630 > "$out/steam_appid.txt"
    mkdir -p "$out/steam_settings"
    echo -n 1211630 > "$out/steam_settings/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "The Jackbox Party Pack 7.exe";

  # The jbg/Scaleform engine writes its per-user store (settings + minimal
  # save state; jbg.config.jet uaAppId "tjpp7loader", loadSaveOnLaunch:true)
  # under the Windows user profile. NOTE: exact path still unverified - the
  # menu reaches START without writing anything, so confirming the path
  # needs an interactive play-through (change a setting, then diff
  # drive_c/users/steamuser per the workflow saveLocations procedure) and a
  # correction before the master init. AppData/Roaming is the best guess;
  # it may instead be AppData/LocalLow/<uaAppId>.
  saveLocations = [ "AppData/Roaming/The Jackbox Party Pack 7" ];

  env = {
    # Pin the appid gbe_fork reports (gameManifest.json steam.appId =
    # 1211630) so the emulated SteamAPI_Init resolves consistently.
    SteamAppId = "1211630";
    SteamGameId = "1211630";
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
  };

  meta = {
    description = "The Jackbox Party Pack 7 (Jackbox Games 2020, Scaleform GFx, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-jackbox-megapicker";
  };
}
