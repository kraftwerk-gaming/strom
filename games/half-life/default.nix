{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  python3,
}:

self.lib.mkGame { inherit lib pkgs; } {
  name = "half-life";

  src = fetchIpfs {
    cid = "QmeUQvq7qxgmktqQyWR5XmyDEXxayjJaQrEpkMg1P8F1qP";
    fallbackUrl = "https://archive.org/download/half-life_20210825/Half-Life.zip";
    hash = "sha256-29sxE98uie7xn5TpUrGuVz8cv5i99aT64aIffkVh8lc=";
    name = "Half-Life.zip";
  };

  nativeBuildInputs = [
    unzip
    python3
  ];

  buildScript = ''
        mkdir -p "$out/Half-Life"
        unzip -q $src -d "$out"

        # Remove kver.kp - the bundled cert belongs to a different key and
        # confuses the auth check even with IsValid patched
        rm -f "$out/Half-Life/kver.kp"

        # Point WON auth servers to localhost so the dead-server check fails fast
        cat > "$out/Half-Life/woncomm.lst" <<'EOF'
    server
      addr 127.0.0.1:27010
    master
      addr 127.0.0.1:27010
    modserver
      addr 127.0.0.1:27011
    secure
      addr 127.0.0.1:27012
    EOF

        # Patch WONAuth.dll: IsValid, Verify, VerifyCertificate -> always return 1
        python3 << PYEOF
    data = bytearray(open("$out/Half-Life/WONAuth.dll","rb").read())
    for off in [0x43c, 0x45a, 0x4c3]:
        data[off:off+6] = bytes([0xB8,0x01,0x00,0x00,0x00,0xC3])
    open("$out/Half-Life/WONAuth.dll","wb").write(data)
    print("Patched WONAuth.dll")
    PYEOF

        # Bat: inject key (no dashes, as game stores it) then launch at 1280x960
        printf '@echo off\r\nreg add "HKCU\\Software\\Valve\\Half-Life" /v Key /d 3333333333333 /f\r\ncd /d "%%~dp0"\r\nhl.exe -w 1920 -h 1080 %%*\r\n' \
          > "$out/Half-Life/hl_launch.bat"
  '';

  copyGlobs = [ ];

  runtime = "proton";
  executable = "Half-Life/hl_launch.bat";

  preRun = "";

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
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Half-Life (WON v1.1.1.0, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "half-life";
  };
}
