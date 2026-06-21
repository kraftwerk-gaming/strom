{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # SKIDROW pre-installed Everything is Crab v1.0.1 (Odd Dreams Digital,
  # Secret Mode 2026). Unity IL2CPP build with DX12 backend. The repack
  # ships SmokeAPI (sentinel: Plugins/x86_64/.smokeapi_applied + a
  # steam_api64.dll shim alongside the original renamed steam_api64_o.dll)
  # as the Steam DRM bypass; the real steam_api64.dll is what Unity's
  # Steamworks.NET plugin links against, so SmokeAPI is loaded
  # transparently when the engine boots. No launcher wrapper is shipped -
  # `Everything is Crab.exe` is the direct engine entry point.
  #
  # Source mirror chain: gofile.io and megadb (the steamrip primary
  # mirrors) are not reachable from headless agents (gofile gates the
  # download behind a rotating JS-derived wt token, megadb behind a
  # 15-second countdown plus recaptcha). skidrowreloaded.com re-mirrors
  # the same release through mediafire, which serves a direct
  # download2NNN.mediafire.com URL after one HTML parse - that's where
  # this zip came from. The pixeldrain mirror (R5Rsnco3) had been taken
  # down for "malware" at the time of staging, so it isn't a valid
  # fallback URL even though it would be the cleanest CDN.
  src = fetchIpfs {
    cid = "QmUwUvaj5DmqcraPZ74xpepwhx5HbgMCWQweeWM1aMHHXk";
    fallbackUrl = "https://www.mediafire.com/file/c0bp2z465ooa46z/Everything.is.Crab.v1.0.1.zip";
    hash = "sha256-GXtrfO/AexSav8D5P9rB3aF0JCD6ptGhLRbiihOuc0U=";
    name = "everything-is-crab.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "everything-is-crab";

  inherit src;

  nativeBuildInputs = [ unzip ];

  # The zip wraps a single top-level dir ("Everything.is.Crab.v1.0.1/").
  # Strip it so $out/Everything is Crab.exe sits at the root next to the
  # Unity *_Data dir, UnityCrashHandler64.exe, baselib.dll, and the D3D12/
  # subdir that holds D3D12Core.dll (Agility SDK runtime). The zip
  # contains spaces in directory entries so quote the glob.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Everything.is.Crab.v1.0.1/." "$out"/
    test -f "$out/Everything is Crab.exe" \
      || { echo "Everything is Crab.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/Everything is Crab_Data/Plugins/x86_64/steam_api64.dll" \
      || { echo "steam_api64.dll (SmokeAPI shim) missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "Everything is Crab.exe";

  # Unity IL2CPP writes per-user state under
  # %USERPROFILE%\AppData\LocalLow\<companyName>\<productName>\, with
  # companyName/productName read from Everything is Crab_Data/app.info.
  # The repack's app.info pins them as "Odd Dreams Digital" / "Everything
  # is Crab" (verified by reading the file out of the source zip).
  #
  # Known limitation: the game boots into Japanese on first launch.
  # Plugins/x86_64/steam_settings/force_language.txt is set to "english"
  # in the repack, but the engine ignores it and reads its own locale
  # preference out of the LocalLow PlayerPrefs that saveLocations
  # relocates - which is empty on a fresh prefix and falls back to
  # Japanese rather than the system locale. Workaround for users: open
  # the in-game Settings menu after boot and switch the language to
  # English (or whichever locale they want); the choice persists into
  # AppData/LocalLow/Odd Dreams Digital/Everything is Crab/ and
  # survives wineprefix wipes via the saveLocations entry below.
  # A future packaging pass could pre-seed the PlayerPrefs file from
  # buildScript so first launch lands in English, but that requires
  # reverse-engineering Unity's binary PlayerPrefs format and is left
  # for after interactive testing confirms the rest of the wrapper.
  saveLocations = [ "AppData/LocalLow/Odd Dreams Digital/Everything is Crab" ];

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
    # Match the Steam appid the repack's SmokeAPI shim expects (matches
    # Plugins/x86_64/steam_appid.txt and steam_settings/steam_appid.txt).
    SteamAppId = "3526710";
    SteamGameId = "3526710";
  };

  meta = {
    description = "Everything is Crab: The Animal Evolution Roguelite (Odd Dreams Digital 2026, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "everything-is-crab";
  };
}
