{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  # Delta Force: Land Warrior (NovaLogic, 2000) - the third entry in the
  # original voxel-terrain Delta Force series and the GOG re-release of the
  # classic engine (NOT the 2025 free-to-play reboot). Distributed as a single
  # RAR holding GOG's already-installed game tree (no Inno installer to run):
  # Dflw.exe is the no-CD-patched retail binary (DFLW.CD is just a disc-present
  # marker), plus the .pff data archives, terrains, music (Dflwmus.sbf) and the
  # Bink intro (DFLWINT.BIK).
  #
  # NovaLogic's engine renders through DirectDraw + Direct3D (ddraw.dll +
  # d3dimm.dll + d3d8.dll), whose legacy paths grey-screen on modern drivers
  # under Wine. The GOG repack ships dgVoodoo2 (the standard NovaLogic fix) as
  # loose ddraw/d3dimm/d3d8 wrapper DLLs plus dgVoodoo.conf, translating those
  # legacy calls to D3D11. We force those three DLLs native under Proton so Wine
  # loads dgVoodoo's wrappers instead of its builtin ddraw/d3dimm/d3d8.
  src = fetchIpfs {
    cid = "QmYetUwyifXet4hsacsJ4CYZKhUmKGvcXuMrABQjFExnbD";
    fallbackUrl = "https://archive.org/download/delta-force-land-warrior_202605/Delta%20Force%20Land%20Warrior.rar";
    hash = "sha256-hPNSitMmPSWBaeDh1htJf6muAYBay46WEtCuupNMCEE=";
    name = "delta-force-land-warrior.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "delta-force";

  inherit src;

  nativeBuildInputs = [ unar ];

  buildScript = ''
    mkdir -p "$out"

    unar -o "$TMPDIR/rar" "$src"
    cp -r "$TMPDIR/rar/Delta Force Land Warrior"/. "$out"/
    chmod -R u+w "$out"

    # GOG launcher / uninstaller / Galaxy debris: not needed at runtime.
    rm -f "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.script "$out"/goggame-*.ico \
          "$out"/goggame.sdb "$out"/goglog.ini \
          "$out"/unins000.* "$out"/*.lnk "$out"/gog.ico \
          "$out"/support.ico || true

    # dgVoodoo defaults to a real fullscreen mode-switch (FullScreenMode = true)
    # which fights gamescope's nesting and can grey-screen. Render into a window
    # that gamescope scales instead, and pick a broadly-supported dxvk output API.
    substituteInPlace "$out"/dgVoodoo.conf \
      --replace-fail "FullScreenMode                       = true" \
                     "FullScreenMode                       = false" \
      --replace-fail "OutputAPI                            = d3d12_fl12_0" \
                     "OutputAPI                            = d3d11_fl11_0" \
      --replace-fail "CaptureMouse                         = true" \
                     "CaptureMouse                         = false"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (the engine writes its
  # player profile / saves next to Dflw.exe, e.g. dflwplyr.sav, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "dflw.exe";

  # NOTE: on startup the engine pops a single, modal, non-fatal NovaLogic
  # warning -- "Your Windows Virtual Memory swap file is less than the minimum
  # recommended size of 140Mb" -- before drawing its main menu. It stems from
  # the game's legacy free-space/virtual-memory probe (read through the
  # wineserver, not influenceable from /proc/meminfo, sysinfo(2) or the
  # PagingFiles registry value) and is harmless: press Enter / click OK once
  # and the full main menu (Single Player / Novaworld / Multiplayer / A-V
  # Options) renders normally through the bundled dgVoodoo2 wrapper.

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
    # Force dgVoodoo2's bundled DirectDraw/Direct3D wrapper DLLs native so Wine
    # loads them instead of its builtin ddraw/d3dimm/d3d8.
    WINEDLLOVERRIDES = "ddraw,d3dimm,d3d8=n,b";
  };

  meta = {
    description = "Delta Force: Land Warrior (NovaLogic 2000, GOG, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "delta-force";
  };
}
