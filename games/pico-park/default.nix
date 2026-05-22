{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  mono,
  cabextract,
}:

let
  # Steamless: removes SteamStub DRM (the .bind section + encrypted
  # entry-point shim) from Steamworks-protected exes. The archive.org
  # "pico-park-classic" asset bundles a 2022 Steam-DRM-bound build of
  # pico_park.exe (SteamStub Variant 3.1 x86). We strip it at build
  # time so the resulting exe is a plain PE that runs without Steam.
  steamless = fetchurl {
    url = "https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip";
    hash = "sha256-4+LSLgmP8/s1myh2qivtlZbwUB5v9YjL/66Qp20txPU=";
  };

  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redist). pico_park
  # imports d3dx9_43.dll. Wine ships a builtin d3dx9_43 compiled from
  # dlls/d3dx9_36/d3dx_helpers.c that mishandles some DDS-format probes
  # and ends up presenting all-white frames (audio works because that's
  # a separate path). Drop Microsoft's native d3dx9_43.dll next to
  # pico_park.exe and force-load it via WINEDLLOVERRIDES.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };

  # The archive.org "pico-park-classic" asset (5.5 MB) carries the
  # 2016 picojoint/TECOPARK readme.txt and a Steam-re-released
  # pico_park.exe with PE timestamp 2016-05-08 wrapped in SteamStub
  # Variant 3.1 (x86). After unpacking with Steamless the .text entry
  # point sits back inside the original code section (0xfb25d, inside
  # .text 0x1000..0x117c00) and the binary contains no Steamworks SDK
  # symbols at all (`strings | grep -i steam` returns only the in-game
  # "NOW ON STEAM" UI label). So no gbe_fork shim or steam_api.dll
  # plant is needed post-unpack: the original 2016 freeware code path
  # had no Steam linkage, the SteamStub was the only Steam dependency.
  src = fetchIpfs {
    cid = "QmNUoeQQd9tvFuTcCvyheCSasqStkRjRvMH1iz8kErsqNu";
    fallbackUrl = "https://archive.org/download/pico-park-classic/pico_park%20classic.zip";
    hash = "sha256-cP9DEblwnXiJM6WndpsDhw3RI8S6MworHc3ooKTex8E=";
    name = "pico-park-classic.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pico-park";

  inherit src;

  nativeBuildInputs = [
    unzip
    mono
    cabextract
  ];

  # Layout inside the zip is flat: pico_park.exe, readme.txt, save/userdata.lua.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"
    chmod -R u+w "$out"

    # Strip SteamStub DRM from pico_park.exe.
    mkdir -p "$TMPDIR/steamless"
    unzip -q ${steamless} -d "$TMPDIR/steamless"
    # Steamless.CLI.exe needs Steamless.API.dll next to it, not just
    # under Plugins/.
    cp "$TMPDIR/steamless/Plugins/Steamless.API.dll" "$TMPDIR/steamless/"
    ( cd "$TMPDIR/steamless" \
      && mono Steamless.CLI.exe --quiet "$out/pico_park.exe" )
    mv "$out/pico_park.exe.unpacked.exe" "$out/pico_park.exe"

    # Two-stage cabextract of d3dx9_43.dll (32-bit) from the June 2010
    # DirectX redist: outer SFX -> jun2010_d3dx9_43_x86.cab -> d3dx9_43.dll.
    mkdir -p "$TMPDIR/dx"
    cabextract -L -d "$TMPDIR/dx" -F 'jun2010_d3dx9_43_x86.cab' ${directxJun2010}
    cabextract -L -d "$TMPDIR/dx" -F 'd3dx9_43.dll' "$TMPDIR/dx/jun2010_d3dx9_43_x86.cab"
    install -m0644 "$TMPDIR/dx/d3dx9_43.dll" "$out/d3dx9_43.dll"
  '';

  runtime = "proton";
  executable = "pico_park.exe";

  env = {
    # Force native d3dx9_43.dll first; wine's builtin emits all-white
    # frames on some DDS-format probe paths (audio still works).
    WINEDLLOVERRIDES = "d3dx9_43=n,b";
    # DXVK renders pico_park's d3d9 swapchain as all-white. Fall back
    # to wined3d (OpenGL d3d9 translator), which handles the engine's
    # render path correctly.
    PROTON_USE_WINED3D = "1";
  };

  # The 2016 Picojoint/TECOPARK build writes its single save file to
  # ./save/userdata.lua next to the binary, not under
  # drive_c/users/steamuser/... So saves persist via the per-game
  # fuse-overlayfs upper and saveLocations stays empty (same pattern
  # as portal/magicka).
  saveLocations = [ ];

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
    description = "Pico Park (TECOPARK 2016 build, SteamStub-stripped, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pico-park";
  };
}
