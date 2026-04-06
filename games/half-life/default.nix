{
  self,
  lib,
  pkgs,
  fetchIpfs,
  pkgsi686Linux,
  unzip,
}:

let
  gameSrc = fetchIpfs {
    cid = "QmeUQvq7qxgmktqQyWR5XmyDEXxayjJaQrEpkMg1P8F1qP";
    fallbackUrl = "https://archive.org/download/half-life_20210825/Half-Life.zip";
    hash = "sha256-29sxE98uie7xn5TpUrGuVz8cv5i99aT64aIffkVh8lc=";
    name = "half-life.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "half-life";

  ipfsSources = [ gameSrc ];
  src = gameSrc;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q $src -d "$out"
    # Archive contains a top-level "Half-Life" directory; flatten it.
    if [ -d "$out/Half-Life" ]; then
      shopt -s dotglob
      mv "$out/Half-Life"/* "$out"/
      rmdir "$out/Half-Life"
    fi
  '';

  runtime = "proton";
  executable = "hl.exe";
  executableArgs = [ "-gl" "-w" "1920" "-h" "1080" "-full" ];

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
    SteamAppId = "70";
    SteamGameId = "70";
    WINE_LARGE_ADDRESS_AWARE = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    PULSE_LATENCY_MSEC = "60";
  };

  targetPkgs = pkgs: [
    pkgs.freetype
    pkgs.glibc
    pkgs.gamescope
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
    pkgs.openal
    pkgs.systemd
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
    pkgsi686Linux.openal
    pkgsi686Linux.alsa-lib
    pkgsi686Linux.libpulseaudio
  ];

  extraBwrapArgs = [
    "--ro-bind /sys /sys"
    "--bind /run /run"
  ];

  preRun = ''

    # Pre-seed WON CD key. Wine rewrites user.reg from in-memory state on
    # shutdown, so editing it directly does not survive. Instead, import a
    # .reg file through regedit so wine writes the key itself.
    USERREG="$COMPATDATA/pfx/user.reg"
    if [ ! -f "$USERREG" ] || ! grep -q '"Key"="2335402628334"' "$USERREG"; then
      REGFILE=$(mktemp --suffix=.reg)
      cat > "$REGFILE" <<'EOF'
REGEDIT4

[HKEY_CURRENT_USER\Software\Valve\Half-Life\Settings]
"Key"="2335402628334"
"EngineType"=dword:00000001
"ScreenWidth"=dword:00000780
"ScreenHeight"=dword:00000438
"ScreenBPP"=dword:00000020
"LauncherWidth"=dword:00000780
"LauncherHeight"=dword:00000438
"LauncherBPP"=dword:00000020
EOF
      # setsid: $PROTON_RUN's postHook does `kill -9 0`, isolate it.
      setsid sh -c "\"\$PROTON_RUN\" regedit /S '$REGFILE'" >/dev/null 2>&1 || true
      rm -f "$REGFILE"
    fi
  '';

  meta = {
    description = "Half-Life (WON 1.1.1.0, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "half-life";
  };
}
