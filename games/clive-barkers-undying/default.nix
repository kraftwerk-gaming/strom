{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unshield,
  unzip,
}:

let
  # USA retail CD image (UNDYING.ISO, ~629 MB) preserved as a backup of the
  # original 2001 Clive Barker's Undying disc on archive.org. The disc is
  # an ISO9660 filesystem with the bulky UE1 game data (Maps/, Sounds/,
  # Textures/, Core.u) sitting directly at the root, plus an InstallShield
  # 6 setup under setup/ that ships the System/ binaries (Undying.exe,
  # engine .u packages, render DLLs) and the Help/ splash/intro assets.
  # We do not run setup.exe: unshield extracts both CABs offline, and we
  # merge the System/ + Help/ trees with the data already on the disc.
  src = fetchIpfs {
    cid = "QmfEixNEUami9F2aLM56EhzJKv79kDb3dsuCNdM8Drj4qQ";
    fallbackUrl = "https://archive.org/download/clive-barkers-undying-2001/UNDYING.ISO";
    hash = "sha256-K9KMr6dgCDxj3sXRQzdT32BRbdFy5+4sdvHKqzqh5B8=";
    name = "clive-barkers-undying.iso";
  };

  # drennan's Widescreen Fix v1.01 (PCGamingWiki community files entry 1118):
  # recompiled UndyingShellPC.u that fixes the journal page scaling at 16:9
  # so the top lines of Patrick's tome are no longer clipped off-screen. The
  # zip also bundles a GlideDrv.dll which we ignore (we use D3DDrv).
  widescreenFix = fetchIpfs {
    cid = "QmQipZKpDbt6kTJ8SkyR1fc3XZpXBH7NhvE57DSFzh2S57";
    hash = "sha256-AtGGq6FhqAYrvetCb/KnKDt5OiKrfhrRx/po+uMIIME=";
    name = "undyingwidescreenfix101.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "clive-barkers-undying";

  inherit src;

  nativeBuildInputs = [
    p7zip
    unshield
    unzip
  ];

  # 7z reads the ISO9660 filesystem; unshield walks the InstallShield .hdr
  # to extract Program Files\System\* and Program Files\Help\*. After
  # extraction the layout matches what Undying.exe expects (paths in
  # Default.ini are ..\System\*.u, ..\Maps\*.sac, ..\Sounds\*.uax,
  # ..\Textures\*.utx, ..\Music\*.umx). DirectX/, AutoRun/, setup/ and
  # Support/ are install-time tooling, not referenced at runtime. The
  # retail Undying.exe is wrapped in SafeDisc and the wrapper exits with
  # code 1 under modern Wine before reaching game code (it spawns a
  # ~efXXXX.tmp decryptor that anti-tampers itself away), so we swap in
  # the no-DRM patched binary the ISO ships in _CRACK/CRACK.ZIP.
  buildScript = ''
    mkdir -p "$out"

    7z x -o"$TMPDIR/iso" "$src" \
      Core.u Maps Sounds Textures readme.txt Undying.ico Undying.jpg \
      _CRACK/CRACK.ZIP

    7z x -o"$TMPDIR/setup" "$src" setup/data1.hdr setup/data1.cab setup/data2.cab
    unshield -d "$TMPDIR/unshield" x "$TMPDIR/setup/setup/data1.hdr"

    unzip -q "$TMPDIR/iso/_CRACK/CRACK.ZIP" -d "$TMPDIR/crack"

    # ISO root has Maps/, Sounds/, Textures/ and a Core.u that the engine
    # expects under System/. Everything else (the Help splash/intro and
    # the System/ binaries + engine packages) comes out of the unshield
    # tree as Program_Files/{System,Help}/.
    cp -r "$TMPDIR/iso"/Maps "$out"/Maps
    cp -r "$TMPDIR/iso"/Sounds "$out"/Sounds
    cp -r "$TMPDIR/iso"/Textures "$out"/Textures
    cp -r "$TMPDIR/unshield/Program_Files/System" "$out"/System
    cp -r "$TMPDIR/unshield/Program_Files/Help" "$out"/Help
    install -m0644 "$TMPDIR/iso/Core.u" "$out/System/Core.u"
    install -m0644 "$TMPDIR/iso/readme.txt" "$out/readme.txt"
    install -m0755 "$TMPDIR/crack/EA Games/Clive Barker's Undying/System/undying.exe" \
      "$out/System/Undying.exe"

    # Overlay the widescreen-fix UndyingShellPC.u on top of the unshield-extracted
    # stock copy so journal/book pages scale correctly at 16:9.
    unzip -qjo ${widescreenFix} UndyingShellPC.u -d "$out/System"

    chmod -R u+w "$out"

    # UE1 reads Default.ini on first launch and clones it into Undying.ini.
    # Skip the hardware-detection wizard (FirstRun=0 -> non-zero), bump
    # the default 640x480/16bpp to 1920x1080/32bpp, and switch the Glide
    # default to D3D (Glide has no Linux/Proton path; D3DDrv goes through
    # Proton's DXVK/d3d8.dll to Vulkan). Default.ini uses CRLF endings so
    # the $ anchor has to allow a trailing \r, matching the deus-ex package.
    sed -i -E \
      -e 's/^FirstRun=0\r?$/FirstRun=1100\r/' \
      -e 's/^FullscreenViewportX=.*$/FullscreenViewportX=1920\r/' \
      -e 's/^FullscreenViewportY=.*$/FullscreenViewportY=1080\r/' \
      -e 's/^FullscreenColorBits=.*$/FullscreenColorBits=32\r/' \
      -e 's/^WindowedColorBits=.*$/WindowedColorBits=32\r/' \
      -e 's|^GameRenderDevice=SoftDrv.SoftwareRenderDevice\r?$|GameRenderDevice=D3DDrv.D3DRenderDevice\r|' \
      -e 's|^RenderDevice=GlideDrv.GlideRenderDevice\r?$|RenderDevice=D3DDrv.D3DRenderDevice\r|' \
      -e 's|^WindowedRenderDevice=SoftDrv.SoftwareRenderDevice\r?$|WindowedRenderDevice=D3DDrv.D3DRenderDevice\r|' \
      "$out/System/Default.ini"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # Save/ + System/ next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "System/Undying.exe";

  # Force resolution at launch - UE1 ignores Default.ini's FullscreenViewport
  # values when the X server it sees (the nested gamescope) only advertises
  # gamescope's own list of modes, and falls back to the smallest mode.
  # Mirror the deus-ex package's args.
  executableArgs = [
    "-ResX=1920"
    "-ResY=1080"
    "-32bit"
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
    description = "Clive Barker's Undying (DreamWorks Interactive / EA 2001, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "clive-barkers-undying";
  };
}
