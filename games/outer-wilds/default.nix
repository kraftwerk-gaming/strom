{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unar,
  unzip,
  p7zip,
  mono,
}:

let
  # Steamless: tool to remove SteamStub DRM (the .bind section) from
  # Steamworks-protected exes. We use it offline during the build so
  # the resulting OuterWilds.exe is a plain PE that can run without a
  # real Steam install.
  steamless = fetchurl {
    url = "https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip";
    hash = "sha256-4+LSLgmP8/s1myh2qivtlZbwUB5v9YjL/66Qp20txPU=";
  };

  # Goldberg / gbe_fork: drop-in steam_api64.dll replacement that fakes
  # SteamAPI_Init etc. The repack ships its own Mono-injection emu
  # (winmm.dll proxy + OnlineFix64.dll) which causes OuterWilds.exe to
  # exit silently in GE-Proton's wine prefix; we replace it with
  # Goldberg, which is a static DLL replacement and works under proton.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "outer-wilds";

  src = fetchIpfs {
    cid = "Qmb1sbog54M4NwpRf1yg8yp5rqU6QcJXLfiUByytow7diF";
    hash = "sha256-ql4whgvoO3UEow1GI4FFUA2724iCvmc1gvB0+4xn1bg=";
    name = "outer-wilds.rar";
  };

  nativeBuildInputs = [
    unar
    unzip
    p7zip
    mono
  ];

  buildScript = ''
    unar -q -D -o "$TMPDIR" "$src"
    mv "$TMPDIR/Outer Wilds" "$out"
    chmod -R u+w "$out"

    # Strip the SteamStub DRM .bind section from OuterWilds.exe using
    # Steamless. Without this, the DRM stub at the entry point exits
    # the process silently when no real Steam install is present.
    mkdir -p "$TMPDIR/steamless"
    unzip -q ${steamless} -d "$TMPDIR/steamless"
    # Steamless.CLI.exe needs Steamless.API.dll next to it, not just
    # under Plugins/.
    cp "$TMPDIR/steamless/Plugins/Steamless.API.dll" "$TMPDIR/steamless/"
    ( cd "$TMPDIR/steamless" \
      && mono Steamless.CLI.exe --quiet "$out/OuterWilds.exe" )
    mv "$out/OuterWilds.exe.unpacked.exe" "$out/OuterWilds.exe"

    # Drop the repack's OnlineFix Mono-injection emu. Its winmm.dll
    # proxy makes OuterWilds.exe exit at DllMain stage under GE-Proton.
    rm -f "$out/winmm.dll" "$out/OnlineFix64.dll" "$out/OnlineFix.ini" \
      "$out/StubDRM64.dll" "$out/SteamOverlay64.dll"
    rm -rf "$out/[Steam]"

    # Replace steam_api64.dll with Goldberg / gbe_fork. This emu fakes
    # SteamAPI_Init() and friends so the game's Steamworks.NET layer
    # initializes successfully without a real Steam process.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    plugins="$out/OuterWilds_Data/Plugins/x86_64"
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$plugins/steam_api64.dll"

    # Goldberg config: report Outer Wilds as owned (appid 753640) plus
    # the Echoes of the Eye DLC (1622100). Goldberg looks for
    # steam_settings/ next to its steam_api64.dll.
    settings="$plugins/steam_settings"
    mkdir -p "$settings"
    echo -n 753640 > "$settings/steam_appid.txt"
    cat > "$settings/configs.app.ini" <<'EOF'
    [app::dlcs]
    unlock_all=0
    1622100=Outer Wilds - Echoes of the Eye
    EOF
    # Some games look for steam_appid.txt next to the exe too.
    echo -n 753640 > "$out/steam_appid.txt"
  '';

  runtime = "proton";
  executable = "OuterWilds.exe";
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
    description = "Outer Wilds (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "outer-wilds";
  };
}
