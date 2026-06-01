{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  p7zip,
  unzip,
  mono,
}:

let
  src = fetchIpfs {
    cid = "QmRzNSoG7yP2hQHda9LCyqtJVxtxiSjmoqH2XNEKUoTma9";
    fallbackUrl = "https://archive.org/download/signalis_202310/Signalis.rar";
    hash = "sha256-M3AG9OvpKnYtEJUk8LlumojaDwneteVJ9P4QiMPy7uA=";
    name = "Signalis.rar";
  };

  # Steamless (atom0s): static SteamStub DRM unpacker. SIGNALIS.exe is
  # wrapped with SteamStub Variant 3.1 (x64) — a ~206 KB `.bind` section
  # that decrypts/aborts before the game's IL2CPP bootstrap runs, so the
  # Goldberg swap below never gets a chance to fake SteamAPI_Init. We run
  # Steamless.CLI.exe (non-interactive) under mono at build time to strip
  # the stub and decrypt the real .text, then keep the Goldberg DLL for
  # the now-reachable SteamAPI_Init. This release ships a working headless
  # CLI plus the x64 unpacker variants (Variant30/31.x64).
  steamless = fetchurl {
    url = "https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip";
    hash = "sha256-4+LSLgmP8/s1myh2qivtlZbwUB5v9YjL/66Qp20txPU=";
  };

  # gbe_fork (Goldberg fork): drop-in steam_api64.dll that fakes
  # SteamAPI_Init() etc. without a running Steam client. SIGNALIS ships
  # the genuine Valve steam_api64.dll and calls SteamAPI.Init()
  # (Steamworks.NET) before anything else; under GE-Proton with no Steam
  # install that Init fails ("Sys_LoadModule failed to load:
  # steamclient64.dll") and the game quits before IL2CPP/GameAssembly
  # even loads — an instant exit with no Player.log. Goldberg is a static
  # DLL replacement and works under proton (same approach as v-rising).
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "signalis";

  # Signalis (rose-engine 2022). Windows Unity IL2CPP build; the rar
  # ships the standard Unity layout (SIGNALIS.exe + UnityPlayer.dll +
  # GameAssembly.dll + SIGNALIS_Data/) inside a single wrapper dir. No
  # installer.
  inherit src;

  nativeBuildInputs = [
    unar
    p7zip
    unzip
    mono
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/x" "$src"
    # Locate the dir that actually holds SIGNALIS.exe rather than guessing
    # the archive's nesting level with a glob.
    d=$(dirname "$(find "$TMPDIR/x" -name SIGNALIS.exe -print -quit)")
    cp -r "$d"/. "$out"/
    chmod -R u+w "$out"

    # 1) Strip SteamStub with Steamless. The CLI references
    # Steamless.API.dll (which ships under Plugins/), so copy it next to
    # the CLI for mono's assembly resolver. mono runs the .NET CLI
    # headless — no wineprefix needed. The unpacker writes
    # SIGNALIS.exe.unpacked.exe into the working dir.
    mkdir -p "$TMPDIR/steamless"
    unzip -q ${steamless} -d "$TMPDIR/steamless"
    cp "$TMPDIR/steamless/Plugins/Steamless.API.dll" "$TMPDIR/steamless/"
    ( cd "$out" && \
      mono "$TMPDIR/steamless/Steamless.CLI.exe" SIGNALIS.exe )
    test -f "$out/SIGNALIS.exe.unpacked.exe"
    mv -f "$out/SIGNALIS.exe.unpacked.exe" "$out/SIGNALIS.exe"

    # 2) Swap the Valve steam_api64.dll for Goldberg and point it at the
    # SIGNALIS appid. Goldberg reads steam_settings/ next to its DLL.
    # Steamworks.NET resolves steam_api64.dll from the EXE dir (game root)
    # first, then the Unity Plugins dir — place it (and steam_settings) in
    # both so the now-reachable SteamAPI_Init hits Goldberg either way.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    gbdll="$TMPDIR/goldberg/release/regular/x64/steam_api64.dll"
    for plugins in "$out/SIGNALIS_Data/Plugins/x86_64" "$out"; do
      cp "$gbdll" "$plugins/steam_api64.dll"
      mkdir -p "$plugins/steam_settings"
      echo -n 1262350 > "$plugins/steam_settings/steam_appid.txt"
    done

    # Some games also probe for steam_appid.txt next to the exe.
    echo -n 1262350 > "$out/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "SIGNALIS.exe";

  env = {
    SteamAppId = "1262350";
    SteamGameId = "1262350";
  };

  # Signalis saves to AppData/LocalLow per Unity convention.
  saveLocations = [ "AppData/LocalLow/rose-engine/SIGNALIS" ];

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
    description = "Signalis (rose-engine 2022, Unity IL2CPP horror via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "signalis";
  };
}
