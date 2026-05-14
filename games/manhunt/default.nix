{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  python3,
}:

let
  # Manhunt (Rockstar North, 2003 PS2 / 2004 PC) - stealth-horror.
  # archive.org/details/manhunt_202411 ships a pre-installed game tree as a
  # single ISO (no InstallShield / no Setup.exe): the game files sit at the
  # disc root (manhunt.exe + audio/initscripts/levels/mss/pictures dirs
  # plus binkw32.dll/mss32.dll). The ISO's manhunt.exe is dated 2022-11-24,
  # i.e. it has already been run through the bundled patchrun.bat
  # (link.exe -edit -nxcompat:no -dynamicbase:no manhunt.exe), so no
  # Vista/7-era NX-compat patch step is required for Proton. We just 7z x
  # the data we need and drop the Windows-only patcher debris and shortcut
  # urls.
  src = fetchIpfs {
    cid = "QmZy3pG9ASgPh73tdSBr37E3pCBmDPJj4wg8TR2SEraH6D";
    fallbackUrl = "https://archive.org/download/manhunt_202411/Manhunt.iso";
    hash = "sha256-nryzQdkhziaAHwKC1F0tWN8p1NES8+SRRmMJRk1zdKI=";
    name = "manhunt.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "manhunt";

  inherit src;

  nativeBuildInputs = [
    p7zip
    python3
  ];

  # 7z handles ISO 9660 (the archive.org image is a plain data CD; no
  # bootable El Torito, no SafeDisc sectors on this preinstalled rip).
  # Extract everything to $out, then strip the four pieces of disc-only
  # debris that we know aren't game runtime:
  #   patchrun.bat + link.exe + mspdb80.dll : the NX-compat patcher
  #     (already applied to the bundled manhunt.exe; see the modtime).
  #   Fixer.exe                             : community Windows-host
  #     fixer GUI, unrelated to the Proton path.
  #   *.url                                 : Rockstar shortcut links.
  #   Autorun.ico                           : disc autorun icon.
  #
  # Launcher-bypass + 1920x1080 mode-pin patch: manhunt.exe shows
  # the Win32 resolution-picker dialog at startup (DialogBoxParamA at
  # VA 0x4c09d3). No cmdline flag and registry pre-seeding doesn't
  # help — the registry read lives inside the dialog's WM_INITDIALOG
  # handler.  See skip-launcher-patch.py for the annotated patch set:
  #   * VA 0x4c0991 (CMP [0x735EC0],0) → JMP rel32 trampoline.
  #   * VA 0x4c0998 (JNZ 0x4c09e7)     → JMP 0x4c09e7 (skip dialog).
  #   * VA 0x66e086 (.text NOP tail)   → MOV [0x735EB4],31; JMP back.
  # Effect:
  #   - DAT_00735eb0 stays as FUN_00612680()'s "current renderer
  #     mode" index.
  #   - DAT_00735eb4 is pinned to renderer mode 31, which under
  #     wined3d + the gamescope nested 1920x1080 surface resolves to
  #     exactly the 1920x1080@60 32bpp fullscreen entry of the
  #     engine's mode table.  Without this pin DAT_00735eb4 stays at
  #     its BSS-zero default and the engine boots at mode 0 (640x480).
  # Note: trying to force resolution by overwriting the FUN_00612710
  # mode-info buffer with 1920x1080 directly crashes the engine
  # inside FUN_0063ce70 -- the RT pool is allocated based on the
  # mode-table entry the engine picked, so off-table sizes deref
  # NULL.  Going through the proper mode index lets the engine
  # pre-allocate the right pool size.
  buildScript = ''
    mkdir -p "$out"
    7z x -y -o"$out" "$src"
    chmod -R u+w "$out"
    rm -f \
      "$out/patchrun.bat" \
      "$out/link.exe" \
      "$out/mspdb80.dll" \
      "$out/Fixer.exe" \
      "$out/Autorun.ico" \
      "$out"/*.url

    python3 ${./skip-launcher-patch.py} "$out/manhunt.exe"
  '';

  runtime = "proton";
  executable = "manhunt.exe";

  # PCGW lists Documents/Rockstar Games/Manhunt/ as the save location for
  # the PC port; relocate so wineprefix wipes don't lose progress.
  saveLocations = [ "Documents/Rockstar Games/Manhunt" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    # The skip-launcher + mode-pin patch makes the engine pick renderer
    # mode 31, which under wined3d + a 1920x1080 nested surface enumerates
    # to a native 1920x1080@60 32bpp fullscreen entry.  The engine
    # pre-allocates its RT pool at that size, so the swapchain back
    # buffer + depth/stencil all come up at 1080p (no gamescope upscale).
    # Mode index 31 is wined3d-specific; if the host's adapter mode list
    # differs, regenerate by tracing WINEDEBUG=+d3d.
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Manhunt is mouse-look; gamescope's absolute Wayland coordinates
      # confuse the engine's relative-delta camera otherwise.
      "--force-grab-cursor" = true;
    };
  };

  env = {
    # Manhunt is a D3D8 title. Earlier revisions of this package set
    # `d3d8=n` ("native only") under the assumption that DXVK's D8VK
    # d3d8.dll would already be installed into the Proton wineprefix,
    # but GE-Proton's default_pfx only seeds Wine's builtin d3d8 stub
    # (which depends on wined3d.dll). Native-only therefore made the
    # exe fail loader_init with c0000135 ("Library d3d8.dll not found").
    # Allow the builtin fallback so the engine can boot.
    # PCGW notes that the wined3d-based d3d8 can render some environment
    # textures black; we'll address that with a bundled d3d8.dll if it
    # actually manifests in-game (Manhunt is mostly dark anyway).
    # binkw32 + mss32 stay native-first so the engine uses the bundled
    # Bink/Miles libraries, not Wine's stubs.
    WINEDLLOVERRIDES = "d3d8=b,n;binkw32,mss32=n,b";
  };

  meta = {
    description = "Manhunt (Rockstar North 2003 stealth-horror, archive.org preinstalled image, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "manhunt";
  };
}
