{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  fetchzip,
  p7zip,
  wineWow64Packages,
}:

let
  # Build-time wine for the Steamless unpacker pass (see Steamless note
  # below). Proton's bundled wine cannot run inside the Nix build sandbox
  # (32-bit ELF needing the steam-runtime FHS), so we use plain nixpkgs
  # wineWow64, which boots under stdenv with no extra runtime — sufficient
  # for Steamless.CLI.exe, a .NET Framework app that just rewrites the PE.
  buildWine = wineWow64Packages.stableFull;

  # Okami HD (HexaDrive / Capcom, 2017 PC port of the 2006 Clover Studio
  # action-adventure). Steam build (app 587620). Distributed as a single
  # ~11.5 GiB zip with a top-level `Okami/` wrapper directory:
  #   Okami/okami.exe            — thin SteamStub-wrapped launcher stub
  #   Okami/main.dll             — actual game logic
  #   Okami/flower_kernel.dll    — engine kernel
  #   Okami/steam_api64.dll      — the REAL Valve Steam API (not a crack)
  #   Okami/data_pc/...          — asset packs + `movie/` .usm intros
  # buildScript strips the `Okami/` wrapper so `okami.exe` sits at $out root.
  #
  # This archive is essentially a clean Steam install, so it needs TWO
  # layers of DRM stripped at build time:
  #
  # 1. SteamStub (the okami.exe `.bind` section). okami.exe is a thin
  #    SteamStub v3-wrapped launcher whose entry point lives in `.bind`. On
  #    launch the stub forces the builtin steam.exe load order, probes for a
  #    live Steam client, fails the SteamStub ownership check under Proton's
  #    stub steam.exe, and self-terminates BEFORE handing control to .text /
  #    loading main.dll — a clean PROCESS_DETACH with no window (the
  #    "launches then instantly closes" symptom). Fixed (same idiom as
  #    games/bioshock) by stripping the wrapper with atom0s's Steamless,
  #    which restores the original .text entry point.
  #
  # 2. SteamAPI (the bundled steam_api64.dll). With the stub gone the game
  #    reaches its own SteamAPI_Init, but the archive ships the REAL Valve
  #    steam_api64.dll, which pops "Steam must be running to play this game
  #    (SteamAPI_Init() failed)" and quits — there is no Steam client in the
  #    sandbox. Fixed (same idiom as games/endless-legend) by swapping in
  #    gbe_fork's drop-in steam_api64.dll, which fakes SteamAPI_Init and the
  #    ownership check. With both layers gone the game runs offline under
  #    Proton; ProtonDB rates the de-DRM'd game Platinum.
  src = fetchIpfs {
    cid = "QmXsbeevoC5YcmeubAyWr7PAS3GxvEdhbc4jhUw3155cxC";
    fallbackUrl = "https://archive.org/download/okami-hd/Okami.zip";
    hash = "sha256-iARCKVCr31I+tUwKIw8wfhfFIaZxjuzNM6nEAKySu60=";
    name = "okami-hd.zip";
  };

  # gbe_fork: drop-in steam_api64.dll replacement that fakes SteamAPI_Init
  # and the ownership check so the game runs without a Steam client.
  goldberg = fetchurl {
    url = "https://github.com/Detanup01/gbe_fork/releases/download/release-2026_04_25/emu-win-release.7z";
    hash = "sha256-Ly0ZE1X6MQVZnons/Tgq2t4eSml3nUznhxI1Ll8OEoI=";
  };

  # atom0s's Steamless v3.1.0.5 — community SteamStub unpacker. v3.1.0.5
  # ships the Variant31 (SteamStub v3.x) unpacker plugin that handles the
  # modern 2016+ `.bind` wrapper used by this 2017 build. Steamless.CLI.exe
  # is a .NET Framework 4.x app; wineWow64.stableFull bundles wine-mono and
  # runs it at build time without any extra runtime.
  steamless = fetchzip {
    url = "https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip";
    hash = "sha256-XCRHmutPspE/7RgUZmMmUwzTf2pzdhcMaLY0hzytszU=";
    stripRoot = false;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "okami";

  inherit src;

  nativeBuildInputs = [
    p7zip
    buildWine
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/zip"
    7z x -y "$src" -o"$TMPDIR/zip" > /dev/null
    cp -r "$TMPDIR/zip/Okami"/. "$out"/
    chmod -R u+w "$out"

    # Seed steam_appid.txt so gbe_fork resolves the app id (587620) without
    # a Steam client at SteamAPI_Init.
    echo -n 587620 > "$out/steam_appid.txt"

    # Swap the real Valve steam_api64.dll for gbe_fork's emulator.
    mkdir -p "$TMPDIR/goldberg"
    7z x -bd -o"$TMPDIR/goldberg" ${goldberg} > /dev/null
    cp "$TMPDIR/goldberg/release/regular/x64/steam_api64.dll" \
      "$out/steam_api64.dll"

    # Strip the SteamStub v3 wrapper from okami.exe at build time with
    # atom0s's Steamless (see the long note above). Two non-obvious setup
    # steps, mirrored from games/bioshock:
    #   - Wine-mono must be msiexec-installed up front: wine's auto-install
    #     dialog needs a DISPLAY (absent in the Nix sandbox); without it the
    #     .NET app fails to launch with rc=255. `msiexec /quiet` stages
    #     mono-2.0 into the throwaway prefix.
    #   - Steamless.CLI.exe's AssemblyResolve handler only fires after Main
    #     starts, but the Program type's static cctor needs Steamless.API.dll
    #     already on the probe path — so copy it next to the CLI exe.
    echo "running Steamless against okami.exe ..."
    export WINEPREFIX="$TMPDIR/steamless-prefix"
    export WINEARCH=win64
    export WINEDLLOVERRIDES="mshtml="
    export WINEDEBUG=-all
    export HOME="$TMPDIR/home"
    mkdir -p "$WINEPREFIX" "$HOME"

    cp -r ${steamless} "$TMPDIR/steamless"
    chmod -R u+w "$TMPDIR/steamless"
    cp "$TMPDIR/steamless/Plugins/Steamless.API.dll" "$TMPDIR/steamless/"

    monoMsi=$(echo ${buildWine}/share/wine/mono/wine-mono-*.msi)
    wine msiexec /i "$monoMsi" /quiet

    wine "$TMPDIR/steamless/Steamless.CLI.exe" "$out/okami.exe"
    wineserver -w 2>/dev/null || true
    [ -f "$out/okami.exe.unpacked.exe" ] || {
      echo "ERROR: Steamless did not produce okami.exe.unpacked.exe" >&2
      exit 1
    }
    mv "$out/okami.exe.unpacked.exe" "$out/okami.exe"
    chmod 0644 "$out/okami.exe"

    # Verify the SteamStub `.bind` section is gone from the unpacked exe.
    if ${pkgs.binutils-unwrapped}/bin/objdump -h "$out/okami.exe" \
        | grep -q '\.bind'; then
      echo "ERROR: okami.exe still has a .bind (SteamStub) section" >&2
      exit 1
    fi
  '';

  runtime = "proton";
  executable = "okami.exe";

  # Okami HD stores its progress in Steam Cloud "remote" storage; gbe_fork
  # emulates that under %APPDATA%/GSE Saves/<appid>/remote. Relocate the
  # whole GSE Saves tree so progress survives wineprefix wipes.
  saveLocations = [ "AppData/Roaming/GSE Saves" ];

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
    STEAM_COMPAT_APP_ID = "587620";
    SteamAppId = "587620";
  };

  meta = {
    description = "Okami HD (HexaDrive / Capcom 2017, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "okami";
  };
}
