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
  '';

  copyGlobs = [ ];

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # Half-Life/valve/SAVE/* + config.cfg next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "Half-Life/hl.exe";

  # Window mode + resolution: passed straight to hl.exe instead of via a
  # cmd.exe .bat launcher. The bat used to also `reg add` the CD key,
  # but invoking it as the proton entrypoint spawned a visible cmd.exe
  # console alongside hl.exe — gamescope mapped both as top-level
  # surfaces and they fought over input focus inside the nested
  # compositor (the user saw a "reg: operation completed successfully"
  # window plus the game, and lost input after pressing Escape). The
  # CD-key seed is now done via preRun against user.reg directly.
  executableArgs = [
    "-w"
    "1920"
    "-h"
    "1080"
  ];

  preRun = ''
    # Seed the WON CD-key into the wineprefix's user.reg. The 1.1.1.0
    # client checks HKCU\Software\Valve\Half-Life\Key on startup; with
    # the WONAuth.dll patches the value need only be present and parse
    # as a 13-digit string. Equivalent to the old bat's
    #   reg add "HKCU\Software\Valve\Half-Life" /v Key /d 3333333333333 /f
    # but without spawning cmd.exe (see the executableArgs comment).
    USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
    # preRun runs before proton bootstraps the wineprefix on a truly
    # fresh launch, so user.reg may not exist yet — create a minimal
    # header so wine accepts the seeded section on first load. (See
    # MEMORY: feedback_prerun_userreg_bootstrap.)
    if [ ! -f "$USERREG" ]; then
      mkdir -p "$(dirname "$USERREG")"
      {
        printf 'WINE REGISTRY Version 2\n'
        printf ';; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n'
      } > "$USERREG"
    fi
    if ! grep -q 'Valve\\\\Half-Life\]' "$USERREG"; then
      TS=$(date +%s)
      {
        printf '\n[Software\\\\Valve\\\\Half-Life] %s\n' "$TS"
        printf '"Key"="3333333333333"\n'
      } >> "$USERREG"
    fi
  '';

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

  meta = {
    description = "Half-Life (WON v1.1.1.0, via Proton and gamescope)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "half-life";
  };
}
