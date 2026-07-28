{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
  cabextract,
  pkgsi686Linux,
}:

let
  # Microsoft DirectX End-User Runtime (February 2010 redistributable) --
  # the same package winetricks's `directplay` verb pulls, and the same
  # one games/gothic uses for DirectMusic. The native DirectPlay DLLs
  # live in the nested `dxnt.cab` inside the self-extracting outer
  # cabinet, so cabextract reaches them in two stages.
  directxFeb2010 = fetchurl {
    url = "https://web.archive.org/web/20100205120000id_/https://download.microsoft.com/download/E/E/1/EE17FF74-6C45-4575-9CF4-7FC2597ACD18/directx_feb2010_redist.exe";
    hash = "sha256-9tGR6JqWPXzKNPFp0w9J6rmcHtO7ktpz7ENhfKqh6T8=";
    name = "directx_feb2010_redist.exe";
  };

  # The DirectPlay 6 pieces age2_x1.5.exe actually uses: dplayx (it
  # imports DPLAYX.dll by ordinal 1/2/4 = DirectPlayCreate /
  # DirectPlayEnumerateA / DirectPlayLobbyCreateA), the TCP/IP service
  # provider dpwsockx, and dplaysvr, the out-of-process session helper
  # native dplayx spawns to own a hosted session.
  #
  # dpnet/dpnhpast/dpnhupnp/dpmodemx are DirectPlay *8* and unused by
  # this title -- overriding them native additionally hangs wine before
  # the process reaches main(), so they are deliberately left builtin.
  directPlayDlls = [
    "dplayx.dll"
    "dpwsockx.dll"
    "dplaysvr.exe"
  ];

  directPlayNative =
    pkgs.runCommandLocal "directplay-native"
      {
        nativeBuildInputs = [ cabextract ];
      }
      ''
        mkdir -p "$out"
        cabextract -q -L -d . -F dxnt.cab ${directxFeb2010}
        for f in ${lib.concatStringsSep " " directPlayDlls}; do
          cabextract -q -L -d "$out" -F "$f" dxnt.cab
        done
      '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "age-of-empires-ii-the-conquerors";

  src = fetchIpfs {
    cid = "Qmaty9puM8eHXB1qmdHYF7G9dBJNVr6ezV99w5iuNADPxY";
    fallbackUrl = "https://archive.org/download/aoe-2-con/AOE2-CON.zip";
    hash = "sha256-V/IRivuCKy8HUPLIc/n2S9jgsY3vbo5jh6y1wZhbamY=";
    name = "AOE2-CON.zip";
  };

  nativeBuildInputs = [
    unzip
    pkgs.ffmpeg
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q $src -d "$out"
    # Remove third-party hooks that cause problems under Proton/Wine.
    # cnc-ddraw: fails to find a DirectDraw device under gamescope
    # IPXWrapper: hooks networking via loose dpwsockx/dplayerx/wsock32
    # shims. These MUST go: wine resolves a DLL next to the exe before
    # syswow64, so leaving them would shadow the native DirectPlay set
    # preRun installs into the prefix (see the directPlayNative note
    # above). Multiplayer runs over native DirectPlay + TCP/IP instead.
    rm -f "$out/AOE2-CON/age2_x1/ddraw.dll"
    rm -f "$out/AOE2-CON/age2_x1/ddraw.ini"
    rm -f "$out/AOE2-CON/age2_x1/wsock32.dll"
    rm -f "$out/AOE2-CON/age2_x1/mswsock.dll"
    rm -f "$out/AOE2-CON/age2_x1/dpwsockx.dll"
    rm -f "$out/AOE2-CON/age2_x1/dplayerx.dll"
    rm -f "$out/AOE2-CON/age2_x1/ipxwrapper.dll"
    rm -f "$out/AOE2-CON/age2_x1/clokspl.exe"
    rm -f "$out/AOE2-CON/age2_x1/Greetz.exe"
    rm -f "$out/AOE2-CON/age2_x1/spectate.exe"
    rm -f "$out/AOE2-CON/age2_x1/ipxconfig.exe"
    rm -f "$out/AOE2-CON/age2_x1/cnc-ddraw config.exe"
    rm -rf "$out/AOE2-CON/age2_x1/Shaders"
    # Replace intro AVI videos (Indeo Video 5, unsupported in Wine) with
    # 0.1-second black stub AVIs using msvideo1 (built-in Wine VFW codec).
    # Encodes in milliseconds; the game skips past them instantly.
    for avi in "$out/AOE2-CON/Avi/"*.AVI "$out/AOE2-CON/Avi/"*.avi; do
      [ -f "$avi" ] || continue
      ffmpeg -f lavfi -i color=black:size=320x240:duration=0.1:rate=15 \
        -vcodec msvideo1 -acodec pcm_u8 -ar 22050 -ac 1 -y "$avi"
    done
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # next to its binary, not under drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "AOE2-CON/age2_x1/age2_x1.5.exe";

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
    PROTON_USE_WINED3D = "1";
    # dplayx/dpwsockx native: wine's builtin dplayx returns E_NOTIMPL from
    # IDirectPlay4::Open(DPOPEN_CREATE), so hosting a TCP/IP game fails and
    # session enumeration comes back empty -- i.e. multiplayer is dead on
    # builtins even though the service-provider list populates fine. The
    # native DX6 DLLs preRun drops into the prefix host and enumerate
    # correctly. `n,b` so a missing DLL still falls back to builtin.
    WINEDLLOVERRIDES = "ddraw=b;dplayx=n,b;dpwsockx=n,b";
    STAGING_WRITECOPY = "1";
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  # wined3d cannot create 8bpp palettized (P8_UINT) surfaces required by
  # AoE2. Set DirectDrawRenderer=gdi (software) in the Wine registry so
  # Wine uses GDI rendering for DirectDraw, which handles 8bpp correctly.
  # user.reg uses Wine registry format: paths relative to HKEY_CURRENT_USER.
  preRun = ''
    reg_file="$STROM_COMPATDATA/0/pfx/user.reg"
    if ! grep -q 'DirectDrawRenderer' "$reg_file" 2>/dev/null; then
      printf '\n[Software\\\\Wine\\\\Direct3D]\n"DirectDrawRenderer"="gdi"\n' \
        >> "$reg_file" 2>/dev/null || true
    fi

    # Native DirectPlay 6 for multiplayer. This is winetricks's `directplay`
    # verb done the way this repo requires (no winetricks/regsvr32 at
    # runtime -- preRun runs outside proton's FHS chroot, so wine binaries
    # can't resolve their 32-bit interpreter here anyway). No COM
    # registration is needed: wine already registers CLSID_DirectPlay and
    # CLSID_DirectPlayLobby against C:\windows\system32\dplayx.dll, which is
    # exactly the path these natives take over, and the game reaches
    # DirectPlay through DirectPlayCreate rather than CoCreateInstance.
    # Sentinel-gated so a wiped prefix re-installs and a warm one doesn't.
    DP_SENTINEL="$STROM_COMPATDATA/0/pfx/.strom-directplay-installed"
    SYSWOW64="$STROM_COMPATDATA/0/pfx/drive_c/windows/syswow64"
    if [ -d "$SYSWOW64" ] && [ ! -e "$DP_SENTINEL" ]; then
      echo "[strom] age-of-empires-ii: installing native DirectPlay 6"
      for f in ${lib.concatStringsSep " " directPlayDlls}; do
        if [ -f "${directPlayNative}/$f" ]; then
          # Move wine's builtin aside rather than deleting it, so the
          # override can be undone by hand without rebuilding the prefix.
          if [ -e "$SYSWOW64/$f" ] || [ -L "$SYSWOW64/$f" ]; then
            mv -f "$SYSWOW64/$f" "$SYSWOW64/$f.builtin" 2>/dev/null || true
          fi
          cp "${directPlayNative}/$f" "$SYSWOW64/$f"
          chmod 644 "$SYSWOW64/$f"
        fi
      done
      touch "$DP_SENTINEL"
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
    pkgs.libxau
    pkgs.libxdmcp
    pkgs.alsa-lib
    pkgs.libpulseaudio
    pkgsi686Linux.freetype
    pkgsi686Linux.glibc
    pkgsi686Linux.glib
    pkgsi686Linux.libx11
    pkgsi686Linux.libxext
    pkgsi686Linux.libxcb
    pkgsi686Linux.libxcursor
    pkgsi686Linux.libxrandr
    pkgsi686Linux.libxi
    pkgsi686Linux.libxfixes
    pkgsi686Linux.libxrender
    pkgsi686Linux.libxcomposite
    pkgsi686Linux.libxinerama
    pkgsi686Linux.libxxf86vm
    pkgsi686Linux.libxau
    pkgsi686Linux.libxdmcp
    pkgsi686Linux.libGL
    pkgsi686Linux.mesa
    pkgsi686Linux.vulkan-loader
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  meta = {
    description = "Age of Empires II: The Conquerors (Classic, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "age-of-empires-ii-the-conquerors";
  };
}
