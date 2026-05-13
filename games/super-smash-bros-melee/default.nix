{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Super Smash Bros. Melee (USA) (En,Ja) (v1.02). GameCube ISO,
  # 1459978240 bytes (1.36 GiB), the standard verified NTSC-U release.
  iso = fetchIpfs {
    cid = "QmNchGZ9oPDdv9DZjtXLkDnvyGoMsPY8rUAwY5eknYCbzb";
    fallbackUrl = "https://archive.org/download/super-smash-bros.-melee-usa-en-ja-v-1.02/Super%20Smash%20Bros.%20Melee%20%28USA%29%20%28En%2CJa%29%20%28v1.02%29.iso";
    hash = "sha256-DeBZgaNBVrnO3O9zxz1CRKwFz2FJqzyc/tkXaYgZ5GQ=";
    name = "super-smash-bros-melee.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "super-smash-bros-melee";

  ipfsSources = [ iso ];
  src = iso;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/melee.iso"
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
    if ! [ -f "$DOLPHIN_USER/Config/GCPadNew.ini" ]; then
      gamepad_name=$(${pkgs.sdl-jstest}/bin/sdl2-jstest --list 2>/dev/null \
        | sed -n "s/^Joystick Name: *'\\(.*\\)'/\\1/p" | head -1)
      if [ -n "$gamepad_name" ]; then
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
    fi

    exec ${pkgs.dolphin-emu}/bin/dolphin-emu \
      --user="$DOLPHIN_USER" \
      --batch \
      --exec="$GAMEDIR/melee.iso"
  '';

  meta = {
    description = "Super Smash Bros. Melee (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "super-smash-bros-melee";
  };
}
