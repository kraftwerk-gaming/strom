{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  _7zz,
}:

let
  src = fetchIpfs {
    cid = "QmUHtxVXCPD2X7p7NG4sxNNewt3V8vEoyYCRw2tuzwryF7";
    fallbackUrl = "https://ipfs.io/ipfs/QmUHtxVXCPD2X7p7NG4sxNNewt3V8vEoyYCRw2tuzwryF7";
    hash = "sha256-CsduiV52QwQ6MFI4nK0ROKWmvq/AhOTciYwg+Q/xHs0=";
    name = "slay-the-spire-2-ankergames.zip";
  };

  # Goldberg / gbe_fork: drop-in steam_api64.dll replacement that fakes
  # SteamAPI_Init etc. The repack ships OnlineFix (winmm.dll proxy +
  # OnlineFix64.dll), whose emulator lacks the SteamTimeline (V001)
  # interface that Steamworks.NET's SteamAPI.InitEx pulls in on this
  # build, so init crashes in EnterBackgroundMode. GBE_fork implements
  # the newer interfaces and is a static DLL swap that works under proton.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "slay-the-spire-2";

  inherit src;

  # AnkerGames zip uses Zstd; needs 7zz, not unzip.
  nativeBuildInputs = [ _7zz ];

  # Layout: <root>/Slay the Spire 2/{SlayTheSpire2.exe,SlayTheSpire2.pck,
  # OnlineFix64.dll,winmm.dll,OnlineFix.ini,dlllist.txt,
  # data_sts2_windows_x86_64/}.  The .NET runtime (coreclr) loads the
  # native steam_api64.dll Steamworks.NET binds to from the
  # data_sts2_windows_x86_64/ dir, not next to the exe.
  buildScript = ''
    mkdir -p "$out"
    7zz x -bso0 -bsp0 "$src" -o"$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Slay the Spire 2/"* "$out"/
    chmod -R u+w "$out"

    # Drop the OnlineFix emulator. Its winmm.dll proxy chain-loads
    # OnlineFix64.dll which spoofs SteamAPI; we replace that whole stack
    # with Goldberg's steam_api64.dll swap (no winmm proxy needed).
    rm -f "$out/winmm.dll" "$out/OnlineFix64.dll" "$out/OnlineFix.ini" \
      "$out/dlllist.txt"

    # Replace steam_api64.dll with Goldberg / gbe_fork. Goldberg looks
    # for steam_settings/ next to its steam_api64.dll.
    mkdir -p "$TMPDIR/goldberg"
    7zz x -bso0 -bsp0 "${goldberg}" -o"$TMPDIR/goldberg"
    plugins="$out/data_sts2_windows_x86_64"
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$plugins/steam_api64.dll"

    # Goldberg config: real appid 2868840, no networking (single-player,
    # avoids any ownership-download/connection gate).
    settings="$plugins/steam_settings"
    mkdir -p "$settings"
    echo -n 2868840 > "$settings/steam_appid.txt"
    cat > "$settings/configs.main.ini" <<'EOF'
    [main::connectivity]
    disable_networking=1
    offline=1
    EOF

    # Goldberg reads the ownership appid from steam_appid.txt; provide it
    # both next to its dll and next to the exe.
    echo -n 2868840 > "$out/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "SlayTheSpire2.exe";

  # Match the bundled launch_vulkan.bat. Godot's d3d12 default black-screens
  # under gamescope/vkd3d (CreateSwapChainForComposition is unimplemented);
  # the native Vulkan renderer draws correctly.
  executableArgs = [
    "--rendering-driver"
    "vulkan"
  ];

  saveLocations = [
    "AppData/Roaming/SlayTheSpire2"
    "AppData/Local/Sentry"
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
    description = "Slay the Spire 2 (MegaCrit 2025, Early Access v0.103.2, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "slay-the-spire-2";
  };
}
