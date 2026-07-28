# dolphin wrapperModule (raw module source).
#
# Wraps Dolphin for GameCube / Wii emulation. The wrapped binary IS
# dolphin-emu; the disc image path is a typed option (isoPath) passed via
# --exec. Dolphin's user directory is per-game
# ($STROM_GAMEDIR/dolphin-user), so memory cards, save states and Wii NAND
# live with the game rather than in the user's global ~/.local/share.
#
# Config seeding is write-if-absent, NOT overwrite-every-launch (which is
# what pcsx2.nix does): Dolphin owns these files at runtime, rewrites them
# on exit, and remapping a controller through its GUI is the normal way to
# adjust a couch setup. Clobbering them each launch would throw that away.
#
# Usage as a sub-option submodule:
#   lib.types.submoduleWith {
#     specialArgs = { inherit wlib; };
#     modules = [ wlib.modules.wrapper wlib.modules.meta (import ./dolphin.nix) ];
#   }
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  _class = "wrapper";

  options = {
    isoPath = mkOption {
      type = types.str;
      description = "Path to the disc image. May contain shell variables (e.g. $STROM_OVERLAY/foo.iso). Dolphin accepts .iso, .gcm, .ciso, .rvz, .wbfs.";
    };

    extraIni = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra Dolphin.ini fragments appended to the seeded base ini
        (per-game tweaks). Only used on first run, when Dolphin.ini does
        not exist yet. Section headers must start at column 0 — Dolphin's
        IniFile::Load does not strip leading whitespace.
      '';
    };

    seedGamepad = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Pre-seed GCPadNew.ini from the first SDL gamepad found at launch,
        so a fresh install is playable without opening Options →
        Controllers. Set false for games that ship their own mapping.
      '';
    };
  };

  config = {
    package = config.pkgs.dolphin-emu;
    exePath = "${config.pkgs.dolphin-emu}/bin/dolphin-emu";
    binName = lib.mkDefault "dolphin-emu";

    preHook = ''
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
        cat ${config.pkgs.writeText "dolphin-extra.ini" config.extraIni} \
          >> "$DOLPHIN_USER/Config/Dolphin.ini"
      fi
    ''
    + lib.optionalString config.seedGamepad ''

      # Detect a plugged SDL gamepad and pre-seed GCPadNew.ini with both
      # the gamepad bindings (mirrors the bundled "SDL Gamepad" profile)
      # AND keyboard fallback (Dolphin's own Linux defaults). Without
      # this Dolphin only auto-binds keyboard; the user would have to
      # open Options → Controllers to assign a gamepad each fresh
      # install.
      if ! [ -f "$DOLPHIN_USER/Config/GCPadNew.ini" ]; then
        gamepad_name=$(${config.pkgs.sdl-jstest}/bin/sdl2-jstest --list 2>/dev/null \
          | sed -n "s/^Joystick Name: *'\(.*\)'/\1/p" | head -1)
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
    '';

    args = [
      "--user=$STROM_GAMEDIR/dolphin-user"
      "--batch"
      "--exec=${config.isoPath}"
    ];
  };
}
