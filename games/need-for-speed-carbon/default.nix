{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  cabextract,
  p7zip,
}:

let
  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # NFS Carbon (an April-2006-era D3DX build) drives its renderer through
  # the D3DX9 effect framework and loads BOTH d3dx9_30.dll and d3dx9_43.dll.
  # Wine's builtin d3dx9 hits a hard assertion in its ID3DXEffectPool
  # implementation (_wassert "iface->lpVtbl == &ID3DXEffectPool_Vtbl",
  # d3dx9_36/effect.c -- the source file name is shared across every
  # d3dx9_NN) and aborts the process before any frame is drawn. The effect
  # pool created by one d3dx9 module is consumed by the other, so BOTH have
  # to be the native Microsoft DLL or the vtable check fails. The documented
  # community fix (winetricks `d3dx9`) installs the native MS d3dx9 set; we
  # extract d3dx9_30 + d3dx9_43 and bind them native.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };

  # Inner-cab name for each native d3dx9 DLL the game loads.
  d3dx9Cabs = {
    "d3dx9_30" = "Apr2006_d3dx9_30_x86.cab";
    "d3dx9_43" = "Jun2010_d3dx9_43_x86.cab";
  };

  # ASI mods (loaded from scripts/ by the dinput8 Ultimate ASI Loader) to
  # DISABLE by renaming them out of the loader's *.asi search set.
  #
  # SpeedReflect.asi (a real-time road/vehicle/mirror reflection mod) crashes
  # the game the instant in-race gameplay loads: the menu and d3d9 init are
  # fine, but starting a Race / Free Roam faults with
  #   page fault on read at 0x00767fe7: movl 8(%esi),%ecx  ESI=0
  #   =>0 nfsc+0x367fe7  1 nfsc+0x368583  2 nfsc+0x2b8f98
  # i.e. the mod's hook into NFSC.exe's renderer dereferences a NULL object on
  # the first in-race frame. Bisected by disabling all five ASIs (race loads),
  # then re-enabling them: with only SpeedReflect removed the race runs and the
  # other four mods (WidescreenFix, ExtraOptions, ExtendedCustomization,
  # NFSCUnlimiter) stay active. SpeedReflect's reflection rendering is the
  # documented weak spot under wined3d, so it is dropped rather than the whole
  # stack.
  disabledAsis = [
    "SpeedReflect.asi"
  ];
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "need-for-speed-carbon";

  # Pre-installed, pre-cracked PC build (NoCD NFSC.exe) bundled with the
  # community ASI mod stack loaded through dinput8.dll: NFSCExtraOptions,
  # NFSCUnlimiter, NFSCarbon.WidescreenFix and ExtendedCustomization (the
  # fifth, SpeedReflect, is disabled at build time -- see disabledAsis below).
  # Ships as a flat game tree (double-nested
  # "Need for Speed - Carbon/Need for Speed - Carbon/") so the build is a
  # single 7z extraction with no installer or wine bootstrap.
  src = fetchIpfs {
    cid = "Qmb6B7BWnVvJLSywmPWHVB7J5qP3abc26aWvkN6Hz9VEWu";
    fallbackUrl = "https://archive.org/download/need-for-speed-carbon.-7z/Need%20for%20Speed%20-%20Carbon.7z";
    hash = "sha256-r/Imcw2RO6sMFZQ4MtSZFDir6ijYav0ha8nApuAVyt4=";
    name = "nfsc.7z";
  };

  nativeBuildInputs = [
    p7zip
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out"
    7z x -y "$src" -o"$TMPDIR/extract"

    game_dir="$TMPDIR/extract/Need for Speed - Carbon/Need for Speed - Carbon"
    if [ -d "$game_dir" ]; then
      mv "$game_dir"/* "$out"/
    else
      echo "unexpected archive layout" >&2
      ls "$TMPDIR/extract" >&2
      exit 1
    fi

    # Rename the crash-inducing ASI mods (see disabledAsis above) out of the
    # loader's *.asi search set so the dinput8 ASI loader skips them.
    ${lib.concatMapStringsSep "\n" (asi: ''
      if [ -f "$out/scripts/${asi}" ]; then
        mv "$out/scripts/${asi}" "$out/scripts/${asi}.disabled"
      fi
    '') disabledAsis}

    # Two-stage cabextract of the native 32-bit d3dx9 DLLs from the June
    # 2010 DirectX redist: outer SFX cabinet -> <inner>.cab, then that inner
    # cab -> <dll>. Staged into the game dir so preRun can install them into
    # the prefix's syswow64 on first launch.
    mkdir -p "$TMPDIR/dx"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (dll: cab: ''
        cabextract -L -d "$TMPDIR/dx" -F '${cab}' ${directxJun2010}
        cabextract -L -d "$TMPDIR/dx" -F '${dll}.dll' \
          "$TMPDIR/dx/${lib.toLower cab}"
        install -m0644 "$TMPDIR/dx/${dll}.dll" "$out/${dll}.dll"
      '') d3dx9Cabs
    )}
  '';

  copyGlobs = [ ];

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (the engine writes
  # its profile/save data next to its binary, like the other NFS-era
  # titles, not under drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "NFSC.exe";

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

  # PROTON_USE_WINED3D=1: NFS Carbon's d3d9 path hits a black screen /
  # heavy glitching under DXVK's d3d9 (doitsujin/dxvk#1295, #3306). The
  # canonical ProtonDB/community fix is to force wined3d, which renders
  # the menu and game correctly.
  #
  # dinput8 native,builtin: the bundled dinput8.dll is the ASI loader that
  # pulls in the WidescreenFix / ExtraOptions / Unlimiter mods; bind the
  # native DLL so Wine loads it instead of its own builtin.
  #
  # d3dx9_30 / d3dx9_43 native,builtin: bind the Microsoft native d3dx9
  # DLLs installed by preRun instead of Wine's builtin, whose ID3DXEffectPool
  # implementation aborts NFSC.exe on startup (see directxJun2010 above).
  env = {
    PROTON_USE_WINED3D = "1";
    WINEDLLOVERRIDES = "dinput8=n,b;d3dx9_30=n,b;d3dx9_43=n,b";
    STEAM_COMPAT_CONFIG = "sdlinput";
    PULSE_LATENCY_MSEC = "60";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # NFSC.exe resolves the d3dx9 DLLs through the Windows loader search path,
  # which can hit syswow64 (the wow6432 redirect of system32) before the
  # app directory. Copy the native MS DLLs staged in the overlay into the
  # prefix's syswow64 on first launch so the d3dx9_*=n,b overrides always
  # bind the native implementation rather than Wine's asserting builtin.
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    if [ -d "$pfx/drive_c/windows/syswow64" ]; then
      for dll in d3dx9_30 d3dx9_43; do
        if [ -f "$STROM_OVERLAY/$dll.dll" ]; then
          install -m0644 "$STROM_OVERLAY/$dll.dll" \
            "$pfx/drive_c/windows/syswow64/$dll.dll"
        fi
      done
    fi
  '';

  meta = {
    description = "Need for Speed: Carbon (2006) (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "need-for-speed-carbon";
  };
}
