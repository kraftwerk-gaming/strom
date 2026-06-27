{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Pikmin (USA). Verified redump GameCube dump, stored as a CISO
  # (compact ISO, 669024832 bytes / 638 MiB) which Dolphin loads
  # natively. The standard NTSC-U release (GPIE01).
  iso = fetchIpfs {
    cid = "Qmd1bP4XPoia96JkSFwpZ6UxoCMETLm1gLor4NcNocQAiC";
    fallbackUrl = "https://archive.org/download/pikmin-usa/Pikmin%20%28USA%29%20.ciso";
    hash = "sha256-sbrhkzaVEUPLdHd9FB3zvHbenYUQSpm81FvLIapawsM=";
    name = "pikmin.ciso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pikmin";

  ipfsSources = [ iso ];
  src = iso;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/pikmin.ciso"
  '';

  runtime = "native";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  runScript = ''
    DOLPHIN_USER="$STROM_GAMEDIR/dolphin-user"
    mkdir -p "$DOLPHIN_USER/Config"

    # Skip the analytics opt-in dialog on first run. Dolphin auto-creates
    # the rest of Dolphin.ini on startup; SIDevice0=6 (Standard
    # Controller) is the default but pinned for safety.
    if ! [ -f "$DOLPHIN_USER/Config/Dolphin.ini" ]; then
      # Note: Dolphin's INI parser does NOT strip leading whitespace
      # (`if (line[0] == '[')` in IniFile::Load), so section headers
      # must start at column 0 — printf avoids the heredoc indent trap.
      printf '%s\n' \
        '[Analytics]' \
        'PermissionAsked = True' \
        'Enabled = False' \
        '[Core]' \
        'SIDevice0 = 6' \
        > "$DOLPHIN_USER/Config/Dolphin.ini"
    fi

    # Detect a plugged SDL gamepad and pre-seed GCPadNew.ini with both
    # the gamepad bindings (mirrors the bundled "SDL Gamepad" profile)
    # AND keyboard fallback (Dolphin's own Linux defaults). Without
    # this Dolphin only auto-binds keyboard; the user would have to
    # open Options → Controllers to assign a gamepad each fresh
    # install.
    gamepad_name=$(${pkgs.sdl-jstest}/bin/sdl2-jstest --list 2>/dev/null \
      | sed -n "s/^Joystick Name: *'\\(.*\\)'/\\1/p" | head -1)
    if [ -n "$gamepad_name" ] \
      && ! ${pkgs.gnugrep}/bin/grep -qs 'Device = SDL/' "$DOLPHIN_USER/Config/GCPadNew.ini"; then
      kbd="XInput2/0/Virtual core pointer"
        printf '%s\n' \
          "[GCPad1]" \
          "Device = SDL/0/$gamepad_name" \
          "Buttons/A = \`Button A\` | \`$kbd:X\`" \
          "Buttons/B = \`Button B\` | \`$kbd:Z\`" \
          "Buttons/X = \`Button X\` | \`$kbd:C\`" \
          "Buttons/Y = \`Button Y\` | \`$kbd:S\`" \
          "Buttons/Z = \`Shoulder R\` | \`$kbd:D\`" \
          "Buttons/Start = \`Start\` | \`$kbd:Return\`" \
          "Main Stick/Up = \`Left Y+\` | \`$kbd:Up\`" \
          "Main Stick/Down = \`Left Y-\` | \`$kbd:Down\`" \
          "Main Stick/Left = \`Left X-\` | \`$kbd:Left\`" \
          "Main Stick/Right = \`Left X+\` | \`$kbd:Right\`" \
          "Main Stick/Calibration = 100.00" \
          "C-Stick/Up = \`Right Y+\` | \`$kbd:I\`" \
          "C-Stick/Down = \`Right Y-\` | \`$kbd:K\`" \
          "C-Stick/Left = \`Right X-\` | \`$kbd:J\`" \
          "C-Stick/Right = \`Right X+\` | \`$kbd:L\`" \
          "C-Stick/Calibration = 100.00" \
          "Triggers/L = \`Trigger L\` | \`$kbd:Q\`" \
          "Triggers/R = \`Trigger R\` | \`$kbd:W\`" \
          "Triggers/L-Analog = \`Trigger L\`" \
          "Triggers/R-Analog = \`Trigger R\`" \
          "D-Pad/Up = \`Pad N\` | \`$kbd:T\`" \
          "D-Pad/Down = \`Pad S\` | \`$kbd:G\`" \
          "D-Pad/Left = \`Pad W\` | \`$kbd:F\`" \
          "D-Pad/Right = \`Pad E\` | \`$kbd:H\`" \
          "Rumble/Motor = \`Motor L\` | \`Motor R\`" \
          > "$DOLPHIN_USER/Config/GCPadNew.ini"
    fi

    exec ${pkgs.dolphin-emu}/bin/dolphin-emu \
      --user="$DOLPHIN_USER" \
      --batch \
      --exec="$GAMEDIR/pikmin.ciso"
  '';

  meta = {
    description = "Pikmin (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pikmin";
  };
}
