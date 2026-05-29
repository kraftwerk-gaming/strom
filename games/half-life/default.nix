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

        # Patch hl.exe: force the CD-key entry dialog to be skipped.
        #
        # The 1.1.1.0 hl.exe gate runs in the function at VA 0x4220f6:
        #   * Reads HKCU\Software\Valve\Half-Life\Settings\Key into a
        #     local CString (via Registry_GetString at 0x4250a0) unless
        #     `-steam` is on the cmdline.
        #   * Tests CString::IsEmpty() at 0x422254.
        #   * If empty, falls into a dialog loop at 0x422261 that calls
        #     LoadString id 0x162 = "Please type in the CD Key displayed
        #     on the Half-Life CD case" then spawns the modal entry
        #     dialog via the CreateDialogIndirectParamA wrapper at
        #     0x49680c.
        #   * If non-empty, jumps to 0x4224fd which calls the validator
        #     at 0x422a1a (strlen==13 + WON checksum at 0x401000) and
        #     either re-prompts or proceeds.
        #
        # Seeding the registry alone does not work: HL re-initialises
        # the Settings subkey early in startup and overwrites our
        # `Key` value with `""`. So we patch the IsEmpty test instead.
        #
        # Original:
        #   0x42225b: 0F 84 9C 02 00 00     je 0x4224fd  ; (jump if non-empty)
        # Patched (force unconditional jump):
        #   0x42225b: E9 9D 02 00 00 90     jmp 0x4224fd ; nop
        # (jmp rel32 is 5 bytes vs je 6, so we displace by +1 and tail
        # with a NOP to keep instruction-stream alignment.)
        #
        # We also patch the validator at VA 0x422a1a to always return 1,
        # so the post-jump `0x4224fd` path (which still runs the strlen
        # + checksum check) accepts the placeholder registry value
        # without needing it to be a genuine WON-checksum-valid key.
        # That keeps everything table-driven: any seed survives, including
        # the empty `""` HL writes for Settings\Key on first launch.
        python3 << PYEOF
    hl_path = "$out/Half-Life/hl.exe"
    data = bytearray(open(hl_path, "rb").read())

    # Skip-dialog patch: turn the `je 0x4224fd` into `jmp 0x4224fd; nop`.
    off = 0x2225b
    assert data[off:off+6] == b"\x0F\x84\x9C\x02\x00\x00", \
        f"hl.exe skip-dialog pattern mismatch at 0x{off:x}: {data[off:off+6].hex()}"
    data[off:off+6] = bytes([0xE9, 0x9D, 0x02, 0x00, 0x00, 0x90])

    # Validator-stub patch: `mov eax, 1; ret 4` at the prologue.
    off = 0x22a1a
    assert data[off:off+3] == b"\x55\x8B\xEC", \
        f"hl.exe validator pattern mismatch at 0x{off:x}: {data[off:off+8].hex()}"
    data[off:off+8] = bytes([0xB8, 0x01, 0x00, 0x00, 0x00, 0xC2, 0x04, 0x00])

    open(hl_path, "wb").write(data)
    print("Patched hl.exe: CD-key dialog skip at VA 0x42225b + validator stub at VA 0x422a1a")
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
    # Seed an engine-baked WON CD-key into HKCU\Software\Valve\Half-Life
    # and \Settings. The hl.exe patches above already short-circuit the
    # IsEmpty test and the WON-checksum validator so the dialog cannot
    # appear, but keeping a 13-digit baked key in the registry means
    # WONAuth.dll's (separately patched) handshake has a syntactically
    # valid value to send if HL ever reaches it, and it survives any
    # future revert of the hl.exe patches as a fallback.
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
        printf '"Key"="1911111111115"\n'
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
