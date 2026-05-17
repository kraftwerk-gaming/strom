{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  cabextract,
  zstd,
}:

let
  # Pre-installed Bully: Scholarship Edition v1.2 (Rockstar Vancouver 2008
  # PC port, the post-patch retail build). Repacked as a deterministic
  # tar.zst from a clean install tree so the build is a single native
  # extraction step (no wine, no closed-source decoders, no MSI
  # bootstrapping). The tree already includes SilentPatchBully,
  # Bully.WidescreenFix, and modupdater alongside Bully.exe and the full
  # Stream/audio/Movies/Config asset set.
  src = fetchIpfs {
    cid = "QmeTAuvZ3W8FFxiPCGdUarUSouSGWLUhFdDoknhskuZK5u";
    hash = "sha256-cpVEPM89/N+yJCvB/viXAfP3luCkt+JUPuBA51s4Ewg=";
    name = "bully-scholarship-edition.tar.zst";
  };

  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # Bully links against xactengine3_1.dll (XACT3 audio engine, June 2008
  # release). Wine's PE-built xactengine3_1 fork that GE-Proton bundles
  # mis-handles XACT cue mixing and wave-bank streaming, which makes
  # every in-game sound (footsteps, dialogue, ambient loops, the entire
  # music bed) play back as static or aliased garbage. The community fix
  # documented across ProtonDB / PCGamingWiki is to drop Microsoft's
  # native xactengine3_1.dll into the game directory and override the
  # loader to bind it instead of Wine's builtin -- same approach
  # winetricks `xact` uses, but baked in at build time.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "bully-scholarship-edition";

  inherit src;

  nativeBuildInputs = [
    cabextract
    zstd
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --use-compress-program=zstd -xf "$src" -C "$out" --strip-components=1

    # Two-stage cabextract of xactengine3_1.dll (32-bit) from the June
    # 2010 DirectX redist: outer SFX cabinet -> Jun2008_XACT_x86.cab,
    # then that inner cab -> xactengine3_1.dll. Dropping the native MS
    # DLL next to Bully.exe (with the WINEDLLOVERRIDES below) replaces
    # wine's broken builtin xactengine3_1 with the real Microsoft
    # implementation; without this every in-game sound is audibly
    # corrupted.
    mkdir -p "$TMPDIR/dx"
    cabextract -L -d "$TMPDIR/dx" -F 'Jun2008_XACT_x86.cab' \
      ${directxJun2010}
    cabextract -L -d "$TMPDIR/dx" -F 'xactengine3_1.dll' \
      "$TMPDIR/dx/jun2008_xact_x86.cab"
    install -m0644 "$TMPDIR/dx/xactengine3_1.dll" "$out/xactengine3_1.dll"
  '';

  runtime = "proton";
  executable = "Bully.exe";

  # PROTON_USE_WINED3D=1: Bully's heavily-modified d3dx9 shader effects
  # (the d3dx:d3dx_effect_* semi-stub paths in the wine log) hit a black
  # screen under DXVK's d3d9 path. Community reports (ProtonDB / PCGW)
  # converge on forcing wined3d as the canonical fix.
  #
  # WINEDLLOVERRIDES: bind the native xactengine3_1.dll we extracted
  # above instead of Wine's broken builtin (audio is otherwise garbage).
  env = {
    PROTON_USE_WINED3D = "1";
    WINEDLLOVERRIDES = "xactengine3_1=n,b";
  };

  # Bully writes its savegames (FileTableBully + BullyFileN slots) and
  # per-user settings directly under Documents/Bully Scholarship Edition/.
  # Despite the publisher, this 2008 PC port predates the standard
  # Rockstar Documents/Rockstar Games/<Title>/ layout used by GTA IV+
  # and writes at the top level of Documents instead. Relocating that
  # directory into $STROM_GAMEDIR keeps saves alive across wineprefix
  # wipes.
  saveLocations = [ "Documents/Bully Scholarship Edition" ];

  # The HKLM\SOFTWARE\Rockstar Games\Bully Scholarship Edition keys
  # (Language, SerialNum, Version) that the retail installer normally
  # imports. Bully.exe queries them at startup and refuses to launch
  # without a Version value. Inject the keys directly into the prefix's
  # system.reg under Wow6432Node (32-bit registry view on 64-bit prefixes)
  # the first time the launcher runs.
  #
  # Also drop Microsoft's native xactengine3_1.dll into the prefix's
  # syswow64 so WINEDLLOVERRIDES="xactengine3_1=n,b" actually finds a
  # native to bind. Bully calls LoadLibrary("C:\windows\system32\
  # xactengine3_1.dll") with an absolute path, which bypasses the
  # app-directory ($STROM_OVERLAY) search; the loader looks ONLY at
  # syswow64 (wow6432 redirect of system32). Without this hop the
  # override falls back to wine's broken builtin and audio is garbled.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    SYSREG="$pfx/system.reg"
    if [ -f "$SYSREG" ] && ! grep -q 'Rockstar Games\\\\Bully Scholarship Edition' "$SYSREG"; then
      {
        printf '\n[Software\\\\Wow6432Node\\\\Rockstar Games\\\\Bully Scholarship Edition]\n'
        printf '"Language"=dword:00000409\n'
        printf '"SerialNum"="0000-0000-0000-0000"\n'
        printf '"Version"="1.00.0154"\n'
      } >> "$SYSREG"
    fi

    if [ -d "$pfx/drive_c/windows/syswow64" ] && [ -f "$STROM_OVERLAY/xactengine3_1.dll" ]; then
      install -m0644 "$STROM_OVERLAY/xactengine3_1.dll" \
        "$pfx/drive_c/windows/syswow64/xactengine3_1.dll"
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
    description = "Bully: Scholarship Edition (Rockstar Vancouver 2008 PC port, v1.2 + SilentPatch, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "bully-scholarship-edition";
  };
}
