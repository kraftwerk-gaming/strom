{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # Tom Clancy's Rainbow Six (Red Storm 1998), the original tactical
  # shooter. Source is the magipacks.blogspot.com community repack
  # (patch v1.04 + Eagle Watch expansion + CD music): a WinRAR archive
  # holding a two-part Inno Setup 5.4.2 installer
  # (Tom Clancy's Rainbow Six_Repack_Setup.exe + ...-1.bin). innoextract
  # yields a ready-to-run tree under app/: RainbowSix.exe + data/. The
  # repack also bundles a dgVoodoo2 wrapper set (DDraw/D3D8/D3D9/D3DImm),
  # but those are removed at build time — under Proton they hand the
  # engine a null-vtable DirectDraw object; Wine's builtin ddraw works.
  # sys/ holds the Voxware voice codecs (vct32150.dll et al.) that
  # RainbowSix.exe statically imports — the original installer copies
  # them into the Windows system dir; we drop them next to the exe
  # instead (Wine searches the app dir first).
  src = fetchIpfs {
    cid = "QmY1hSdRXiBikBw7zskLtgDW25G14YsKmwxVXNFhx1hJvh";
    fallbackUrl = "https://archive.org/download/tom-clancys-rainbow-six_202605/Tom%20Clancy%27s%20Rainbow%20Six.rar";
    hash = "sha256-hJUiwKIhdO6htWn3BL+YK2nfhkG79Zbb68Rn9VJHbBY=";
    name = "rainbow-six.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "rainbow-six";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  # unar the WinRAR archive, then innoextract the nested Inno installer.
  # The setup .exe name carries a curly apostrophe (U+2019); glob it.
  # The game tree is the installer's app/ directory; copy it to $out root.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/rar"
    unar -o "$TMPDIR/rar" "$src"
    innoextract -d "$TMPDIR/iss" "$TMPDIR/rar/"*/*Repack_Setup.exe
    cp -r "$TMPDIR/iss/app"/. "$out"/
    # RainbowSix.exe imports the Voxware codec DLLs that ship under sys/;
    # place them next to the binary so the import loader finds them.
    cp "$TMPDIR/iss/sys"/. "$out"/ -r
    chmod -R u+w "$out"

    # Drop the repack's bundled dgVoodoo2 wrapper set so the engine binds
    # Wine's builtin ddraw (forced native, dgVoodoo faults under Proton).
    rm -f "$out/DDraw.dll" "$out/D3D8.dll" "$out/D3D9.dll" \
          "$out/D3DImm.dll" "$out/dgVoodoo.conf" "$out/dgVoodooCpl.exe"

    # The v1.04 engine hardcodes its asset paths as InstallationPath\data2\*
    # (data2\map, data2\sound, data2\text\..., etc.), but the repack's
    # installer lays the tree down under data\. Rename it so the engine
    # finds its maps/bitmaps/sounds; otherwise it loads nothing and exits.
    mv "$out/data" "$out/data2"

    # The menu reaches fine, but entering a mission (campaign or training)
    # crashed RainbowSix.exe at +0x6AD9A on a `read access to 00000074`
    # (a [null+0x74] vtable deref in the renderer). Cause: the engine loads
    # the in-game shell cursor as data2\shell\cursor\Arrow.RSB (capital A)
    # the moment the 3D view initialises, but innoextract lays the file
    # down as arrow.RSB. On strom's fuse-overlayfs Wine disables its
    # case-insensitive lookup fallback (FUSE_SUPER_MAGIC with no .ciopfs
    # marker -> get_dir_case_sensitivity reports case-sensitive, see the
    # overlay-case-insensitivity reference), so the uppercase lookup misses,
    # the cursor surface comes back null, and the renderer faults. Rename the
    # file to the exact case the engine hardcodes so the lookup resolves on
    # the case-sensitive overlay. Verified: training/campaign missions now
    # load the 3D view + HUD instead of crashing, and the menu still works.
    if [ -f "$out/data2/shell/cursor/arrow.RSB" ]; then
      mv "$out/data2/shell/cursor/arrow.RSB" "$out/data2/shell/cursor/Arrow.RSB"
    fi
  '';

  runtime = "proton";

  # The engine writes saves and config into data2/save/ next to the
  # binary, so they persist via the per-game fuse-overlayfs upper; no
  # wineprefix relocation needed.
  saveLocations = [ ];
  executable = "RainbowSix.exe";

  env = {
    # Use Wine's builtin DirectDraw (the bundled dgVoodoo DLLs were
    # removed at build time); builtin ddraw routes the engine's legacy
    # DirectDraw7/Direct3D calls through wined3d -> Vulkan.
    WINEDLLOVERRIDES = "ddraw=b";
  };

  # The 1998 engine calls GetVersion() and refuses to initialise its
  # DirectDraw renderer unless it sees a Win9x platform id; the working
  # Lutris/winecfg recipe is "Windows 98". Seed the authoritative
  # HKCU\Software\Wine "Version"="win98" key (parse_win_version in
  # wine ntdll/version.c) plus the HKLM 9x fallback keys. Proton creates
  # user.reg only after the first wineserver start, so bootstrap a
  # minimal valid file if it is absent.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    mkdir -p "$pfx"
    USERREG="$pfx/user.reg"
    SYSREG="$pfx/system.reg"

    if [ ! -f "$USERREG" ]; then
      printf 'WINE REGISTRY Version 2\n\n' > "$USERREG"
    fi
    if ! grep -qF '[Software\\Wine]' "$USERREG"; then
      {
        printf '\n[Software\\\\Wine] %s\n' "$(date +%s)"
        printf '"Version"="win98"\n'
      } >> "$USERREG"
    fi

    # The engine renders its UI/menu through 8-bit palettized DirectDraw
    # surfaces. wined3d cannot create P8_UINT surfaces, so each surface
    # comes back as a zeroed (null-vtable) object and the engine faults
    # at +0x6AD9A in Surface::SetTransparentValue calling [vtable+0x74].
    # Switch Wine's DirectDraw backend to the GDI software path, which
    # handles 8bpp palettized surfaces correctly (same fix as AoE2).
    if ! grep -qF '[Software\\Wine\\Direct3D]' "$USERREG"; then
      {
        printf '\n[Software\\\\Wine\\\\Direct3D] %s\n' "$(date +%s)"
        printf '"DirectDrawRenderer"="gdi"\n'
      } >> "$USERREG"
    fi

    if [ -f "$SYSREG" ] && ! grep -qF 'R6-WIN98-SEEDED' "$SYSREG"; then
      {
        printf '\n[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion] %s\n' "$(date +%s)"
        printf ';; R6-WIN98-SEEDED\n'
        printf '"VersionNumber"="4.10.2222"\n'
        printf '"SubVersionNumber"=" A "\n'
        printf '"ProductName"="Microsoft Windows 98"\n'
      } >> "$SYSREG"
    fi

    # Run the game inside a Wine virtual desktop (the "Desktop Mode" the
    # Lutris recipe enables) so the engine's DirectDraw mode-set renders
    # into a fixed root window gamescope upscales, instead of trying to
    # switch the (non-switchable, nested) real output.
    if ! grep -qF '[Software\\Wine\\Explorer\\Desktops]' "$USERREG"; then
      {
        printf '\n[Software\\\\Wine\\\\Explorer] %s\n' "$(date +%s)"
        printf '"Desktop"="Default"\n'
        printf '\n[Software\\\\Wine\\\\Explorer\\\\Desktops] %s\n' "$(date +%s)"
        printf '"Default"="640x480"\n'
      } >> "$USERREG"
    fi

    # Force the engine's software renderer. Renderer::CreateDirectDraw()
    # enumerates Direct3D hardware devices and then calls a method off
    # the returned device's null vtable, faulting RainbowSix.exe at
    # +0x6AD9A on `call [vtable+0x74]`. SoftwareOnly=1 makes the renderer
    # take the pure-DirectDraw blit path and skip D3D device creation —
    # the documented "runs only in Software Mode" community fix.
    #
    # The game is 32-bit, so HKLM\Software\... is WoW64-redirected to
    # HKLM\Software\Wow6432Node\... : seeding the un-redirected path is
    # invisible to it (proven: the game creates an empty
    # Wow6432Node\Red Storm Entertainment\Tom Clancy's Rainbow Six key at
    # runtime, defaults SoftwareOnly to 0, and crashes). Seed under the
    # Wow6432Node path in system.reg. HKCU is not WoW-redirected, so seed
    # the plain path there too. Values are REG_SZ "1".
    r6_seed() {
      printf '\n[%s\\\\Red Storm Entertainment\\\\Tom Clancy'"'"'s Rainbow Six] %s\n' "$1" "$(date +%s)"
      printf ';; R6-RENDERER-SEEDED\n'
      printf '"SoftwareOnly"="1"\n'
      printf '"FullScreen"="1"\n'
      printf '"UsePrimaryDisplay"="1"\n'
      printf '"UseDisplayDeviceGuid"="0"\n'
    }
    if ! grep -qF 'R6-RENDERER-SEEDED' "$USERREG"; then
      r6_seed 'Software' >> "$USERREG"
    fi
    if [ -f "$SYSREG" ] && ! grep -qF 'R6-RENDERER-SEEDED' "$SYSREG"; then
      r6_seed 'Software\\Wow6432Node' >> "$SYSREG"
    fi
  '';

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
    description = "Tom Clancy's Rainbow Six (Red Storm 1998, patch v1.04 + Eagle Watch, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rainbow-six";
  };
}
