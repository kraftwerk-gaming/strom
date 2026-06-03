{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  cabextract,
}:

let
  # Microsoft DirectX 9.0c End-User Runtime (June 2010 redistributable).
  # age3*.exe import d3dx9_25.dll (the Apr-2005 DirectX SDK D3DX helper)
  # and drive the entire 3D scene through the D3DX *effects* framework:
  # the Bang! engine's terrain, water, units and buildings are rendered by
  # .fx effect files whose vs_3_0/ps_3_0 shaders are compiled at load time
  # via ID3DXEffectCompiler::CompileShader. Wine's builtin d3dx9 ships only
  # a STUB effect compiler (d3dx9_effect_compiler_init / CompileShader log
  # "implementation is only a stub" and return failure), so under Proton
  # every effect shader silently fails to compile and those surfaces render
  # black/untextured -- which is the "textures missing" symptom (the 2D UI,
  # which uses no .fx effects, draws fine). Ship the real Microsoft
  # d3dx9_25.dll (it implements D3DXCreateEffectCompiler / CompileShader)
  # and force-load it native. Same class of fix as
  # lego-star-wars-the-complete-saga (d3dx9_35) and the winetricks d3dx9_25
  # verb installs this exact DLL.
  directxJun2010 = fetchurl {
    url = "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe";
    hash = "sha256-h0buGoSgg6kON4mdcdUNXHwBXmloikZqqARH8BF4DA0=";
    name = "directx_Jun2010_redist.exe";
  };
  # Age of Empires III was never released on GOG; the retail 2005 "Complete
  # Collection" used SafeDisc + online activation, so a verbatim disc rip
  # will not run under Proton. The ElAmigos archive.org item
  # (age-of-empires-iii-complete-collection / Ag3Emp1r3sIII.rar) is a
  # password-encrypted Inno Setup installer (innoextract reports a password
  # hash on the payload; age3*.exe are "encrypted"), so it cannot be
  # extracted without the per-release ElAmigos password and was a dead end.
  #
  # This source instead is a pre-installed, no-CD-patched game tree shipped
  # as a single zip ("AoE3 without any annoying isos"). It contains the full
  # Bang! engine install with all three executables already SafeDisc-stripped
  # at <zip>/Age.of.Empires.III.Complete.Collection/Age.of.Empires.III.Complete.Collection/bin/.
  src = fetchIpfs {
    cid = "QmZSFvpZ4Z4PzcXccX5eRHU8Y65YGeykNJLcYKtZ4S8dzJ";
    fallbackUrl = "https://archive.org/download/age.of.-empires.-iii.-complete.-collection_202412/Age.of.Empires.III.Complete.Collection.zip";
    hash = "sha256-3Oec4e1F1kA7AXKV/x7VzxjRETs73WAVZWzDHRVuYLY=";
    name = "age-of-empires-iii-complete-collection.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "age-of-empires-iii";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [
    unzip
    cabextract
  ];

  # The zip double-nests the install
  # (Age.of.Empires.III.Complete.Collection/Age.of.Empires.III.Complete.Collection/);
  # flatten it so the engine tree (bin/, with bin/data, bin/Sound, bin/art,
  # bin/Startup) lands directly under $out and executable = "bin/age3.exe".
  buildScript = ''
    mkdir -p "$out"
    tmp=$(mktemp -d)
    unzip -q "$src" -d "$tmp"
    inner="$tmp/Age.of.Empires.III.Complete.Collection/Age.of.Empires.III.Complete.Collection"
    cp -r "$inner"/. "$out"/
    chmod -R u+w "$out"

    # Two-stage cabextract of the native 32-bit d3dx9_25.dll from the
    # June 2010 DirectX redist (outer SFX cabinet -> Apr2005_d3dx9_25_x86.cab
    # -> d3dx9_25.dll). Dropped into bin\ next to age3.exe; the
    # WINEDLLOVERRIDES below binds it native so the D3DX effect compiler the
    # Bang! engine drives its terrain/unit shaders through is the real
    # Microsoft implementation rather than Wine's stub. See the
    # directxJun2010 comment for why.
    cabextract -L -d "$tmp/dx" -F 'Apr2005_d3dx9_25_x86.cab' \
      ${directxJun2010}
    cabextract -L -d "$tmp/dx" -F 'd3dx9_25.dll' \
      "$tmp/dx/apr2005_d3dx9_25_x86.cab"
    install -m0644 "$tmp/dx/d3dx9_25.dll" "$out/bin/d3dx9_25.dll"

    rm -rf "$tmp"
  '';

  runtime = "proton";

  # The Bang! engine writes savegames, recorded games and the user profile
  # under Documents/My Games/Age of Empires 3/ (Savegame/, RecordGames/,
  # Users3/ profile xml). Relocating the whole dir keeps progress alive
  # across wineprefix wipes.
  saveLocations = [
    "Documents/My Games/Age of Empires 3"
  ];

  # Launch the base game (age3.exe). age3x.exe (WarChiefs) and age3y.exe
  # (Asian Dynasties) have heavier first-run init paths; the base exe is
  # the most reliable route to the menu. All three resolve their DATAP*.BAR
  # archives via the SetupPath keys seeded in preRun.
  executable = "bin/age3.exe";

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

  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
    STAGING_WRITECOPY = "1";
    # The Bang! engine renders its 3D world through fixed-function Direct3D9
    # (no programmable shaders for terrain/units). Under Proton's default DXVK
    # the 2D HUD/minimap composites fine but the 3D viewport stays solid black:
    # DXVK does not implement the legacy fixed-function pipeline this engine
    # relies on. PROTON_USE_WINED3D=1 routes D3D9 through wined3d -> OpenGL,
    # whose full fixed-function support makes terrain, units and buildings
    # actually render. Same fix as the other Bang/fixed-function-era titles
    # here (Age of Empires II, Warcraft III).
    PROTON_USE_WINED3D = "1";

    # Bind the native d3dx9_25.dll shipped into bin\ (n = native first,
    # b = fall back to builtin) so the Bang! engine's D3DX effect compiler
    # is the real Microsoft implementation. Without this, Wine's builtin
    # d3dx9 stubs ID3DXEffectCompiler::CompileShader and every terrain/unit
    # effect shader fails to compile, leaving those surfaces untextured
    # (black). See the directxJun2010 comment for the full trace evidence.
    WINEDLLOVERRIDES = "d3dx9_25=n,b";
  };

  # First-run registry seeding. Two distinct gates block reaching the game,
  # both keyed off HK*\Software\Microsoft\Microsoft Games\Age of Empires 3{,
  # Expansion Pack, Expansion Pack 2}\1.0:
  #
  # 1. SetupPath (HKLM/system.reg). age3*.exe abort with "Initialization
  #    failed - Could not load DATAP*.BAR" unless SetupPath points at the bin\
  #    directory. The Bang! engine resolves data archives as SetupPath +
  #    "DataP*.bar" (the .bar files live directly in bin\, not bin\data\), so
  #    SetupPath must be $GAMEDIR\bin\ (verified live: $GAMEDIR alone errors;
  #    appending bin\ reaches the title splash).
  #
  # 2. FIRSTRUN (HKCU/user.reg). Past the splash the engine LoadLibrary's
  #    Eula.dll and calls its sole export EBUEula(lpRegKeyLocation, eulaFile,
  #    warrantyFile, fCheckForFirstRun=1). Decompiled, EBUEula reads the
  #    FIRSTRUN DWORD under HKCU\<lpRegKeyLocation> (falling back to HKLM); if
  #    present it returns "accepted" immediately, otherwise it shows a modal
  #    "End User License Agreement" DialogBox and only writes FIRSTRUN once the
  #    user clicks Accept. That modal is a second Win32 top-level which
  #    gamescope refuses to focus/composite, so it can never be accepted in the
  #    nest and the game hangs on the splash forever. Seeding FIRSTRUN=1 makes
  #    EBUEula skip the dialog; the game then boots straight into the campaign.
  #
  # Both are appended directly as Wine registry text (no regedit / PROTON_RUN,
  # which is not exported at preRun time). proton creates the prefix on first
  # launch, so on a truly fresh prefix the *.reg files do not exist yet and
  # that first launch comes up without the keys; they land on the next launch
  # once proton has bootstrapped the prefix, and persist. GAMEDIR_WIN is the
  # in-prefix Z: path mapping to the fuse-overlayfs $GAMEDIR. SetupPath is
  # written to both the plain and Wow6432Node views so the 32-bit exes resolve
  # it regardless of which view the engine reads.
  preRun = ''
    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
    set -- 'Age of Empires 3' \
      'Age of Empires 3 Expansion Pack' \
      'Age of Empires 3 Expansion Pack 2'
    if [ -f "$SYSREG" ] \
        && ! grep -q 'Microsoft Games\\\\Age of Empires 3\\\\1.0' "$SYSREG"; then
      echo "[strom] first-run setup: seeding SetupPath registry"
      GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}\\\\bin\\\\"
      TS=$(date +%s)
      for base in \
        'Software\\Microsoft\\Microsoft Games' \
        'Software\\Wow6432Node\\Microsoft\\Microsoft Games'; do
        for game in "$@"; do
          {
            printf '\n[%s\\\\%s\\\\1.0] %s\n' "$base" "$game" "$TS"
            printf '"SetupPath"="%s"\n' "$GAMEDIR_WIN"
            printf '"Version"="1.0"\n'
          } >>"$SYSREG"
        done
      done
    fi
    if [ -f "$USERREG" ] \
        && ! grep -q 'Microsoft Games\\\\Age of Empires 3\\\\1.0' "$USERREG"; then
      echo "[strom] first-run setup: seeding EULA FIRSTRUN registry"
      TS=$(date +%s)
      for game in "$@"; do
        {
          printf '\n[Software\\\\Microsoft\\\\Microsoft Games\\\\%s\\\\1.0] %s\n' \
            "$game" "$TS"
          printf '"FIRSTRUN"=dword:00000001\n'
        } >>"$USERREG"
      done
    fi
  '';

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
    pkgs.python3
    pkgs.mesa
    pkgs.vulkan-loader
    pkgs.libGL
    pkgs.libx11
    pkgs.libxext
    pkgs.libxcb
    pkgs.libxcursor
    pkgs.libxrandr
    pkgs.libxi
    pkgs.libxfixes
    pkgs.libxrender
    pkgs.libxcomposite
    pkgs.libxinerama
    pkgs.libxxf86vm
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgs.pkgsi686Linux.freetype
    pkgs.pkgsi686Linux.glibc
    pkgs.pkgsi686Linux.glib
    pkgs.pkgsi686Linux.libx11
    pkgs.pkgsi686Linux.libxext
    pkgs.pkgsi686Linux.libxcb
    pkgs.pkgsi686Linux.libxcursor
    pkgs.pkgsi686Linux.libxrandr
    pkgs.pkgsi686Linux.libxi
    pkgs.pkgsi686Linux.libxfixes
    pkgs.pkgsi686Linux.libxrender
    pkgs.pkgsi686Linux.libxcomposite
    pkgs.pkgsi686Linux.libxinerama
    pkgs.pkgsi686Linux.libxxf86vm
    pkgs.pkgsi686Linux.libGL
    pkgs.pkgsi686Linux.mesa
    pkgs.pkgsi686Linux.vulkan-loader
    pkgs.pkgsi686Linux.alsa-lib
    pkgs.pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Age of Empires III: Complete Collection (via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "age-of-empires-iii";
  };
}
