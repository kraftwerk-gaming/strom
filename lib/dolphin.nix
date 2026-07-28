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

    env = {
      # Run Dolphin on gamescope's nested Xwayland, not its wayland display.
      # Dolphin's keyboard/mouse ControllerInterface device is XInput2 -- an
      # X11-only backend -- so as a wayland client Dolphin exposes NO
      # keyboard device at all and every `XInput2/0/Virtual core pointer`
      # binding silently never fires. That left keyboard-only machines with
      # no usable input (observed on pikmin-2). lib/retroarch.nix forces xcb
      # for a related reason and lib/pcsx2.nix for a rendering one, so this
      # is the established shape for emulators in this tree.
      QT_QPA_PLATFORM = "xcb";
    };

    preHook = ''
      # Same reason as QT_QPA_PLATFORM above: keep Dolphin off the wayland
      # display so its X11-only XInput2 keyboard device exists.
      unset WAYLAND_DISPLAY

      DOLPHIN_USER="$STROM_GAMEDIR/dolphin-user"
      mkdir -p "$DOLPHIN_USER/Config"

      # Enumerate SDL gamepads once as "<sdl-index>\t<name>" lines. The SDL
      # index is read from sdl2-jstest's own "Joystick Number:" field rather
      # than inferred from listing position: Dolphin's device string is
      # "SDL/<index>/<name>", and a non-pad stick (wheel, HOTAS) occupying a
      # low index would otherwise shift every mapping onto the wrong device.
      # sed normalises the two interesting lines first so awk needs no
      # embedded quoting. SDL insists on a video driver even for a
      # joystick-only query and there is no wayland/X yet at preHook time,
      # hence SDL_VIDEODRIVER=dummy.
      pad_list=$(SDL_VIDEODRIVER=dummy ${config.pkgs.sdl-jstest}/bin/sdl2-jstest --list 2>/dev/null \
        | sed -n -e "s/^Joystick Name: *'\(.*\)'/N \1/p" \
                 -e "s/^Joystick Number: *\([0-9][0-9]*\).*/I \1/p" \
        | awk '/^N /{ sub(/^N /, ""); name = $0 } /^I /{ if (name != "") print $2 "\t" name }')
      pad_count=$(printf '%s' "$pad_list" | ${config.pkgs.gnugrep}/bin/grep -c . || true)
      if [ "$pad_count" -gt 4 ]; then
        pad_count=4
      fi

      # Skip the analytics opt-in dialog on first run. Dolphin auto-creates
      # the rest of Dolphin.ini on startup.
      if ! [ -f "$DOLPHIN_USER/Config/Dolphin.ini" ]; then
        # Note: Dolphin's INI parser does NOT strip leading whitespace
        # (`if (line[0] == '[')` in IniFile::Load), so section headers
        # must start at column 0 — printf avoids the heredoc indent trap.
        {
          printf '%s\n' '[Analytics]' 'PermissionAsked = True' 'Enabled = False' '[Core]'
          # One Standard Controller (SIDevice = 6) per detected pad, so
          # local-multiplayer titles actually see ports 2-4 instead of
          # being single-player-only on a couch with four pads. Port 1 is
          # always pinned even with no pad, matching Dolphin's default.
          si_ports=$pad_count
          if [ "$si_ports" -lt 1 ]; then
            si_ports=1
          fi
          i=0
          while [ "$i" -lt "$si_ports" ]; do
            printf 'SIDevice%s = 6\n' "$i"
            i=$((i + 1))
          done
          cat ${config.pkgs.writeText "dolphin-extra.ini" config.extraIni}
        } > "$DOLPHIN_USER/Config/Dolphin.ini"
      fi
    ''
    + lib.optionalString config.seedGamepad ''

      # Pre-seed GCPadNew.ini so a fresh install is playable immediately.
      #
      # Port 1 ALWAYS gets the keyboard binding, whether or not a pad is
      # present, and every detected pad is layered on top (port 1 gets both,
      # ports 2-4 are pad-only since sharing one keyboard across four
      # players is meaningless). Dolphin's own out-of-the-box GC config
      # binds nothing usable here, so a padless machine previously had NO
      # working input at all -- the operator hit exactly that on pikmin-2.
      # This mirrors what lib/pcsx2.nix does for PS2: keyboard alongside
      # the pad, never instead of it.
      #
      # Keyboard keys are Dolphin's own Linux defaults, reached through the
      # XInput2 "Virtual core pointer" device (that is how Dolphin exposes
      # keyboard+mouse on X11, and it is what the two pre-helper Dolphin
      # games used).
      #
      # Seeding runs when there is nothing to preserve. A plain
      # write-if-absent gate is not enough: if the first launch happens with
      # no pad, the file exists afterwards and pad seeding would be skipped
      # forever on that install. So also seed when the file binds no SDL
      # device while a pad is now present. A user who mapped or remapped a
      # pad has `Device = SDL/` lines and is never touched.
      needs_pad_seed=0
      if ! [ -f "$DOLPHIN_USER/Config/GCPadNew.ini" ]; then
        needs_pad_seed=1
      elif [ "$pad_count" -gt 0 ] \
        && ! ${config.pkgs.gnugrep}/bin/grep -q 'Device = SDL/' "$DOLPHIN_USER/Config/GCPadNew.ini"; then
        needs_pad_seed=1
      fi
      if [ "$needs_pad_seed" -eq 1 ]; then
        # shellcheck disable=SC2016 # Dolphin's INI syntax wraps every control
        # reference in literal backticks, so these printf formats must stay
        # single-quoted; nothing in them is meant to expand.
        emit_pad() {
          pad_section=$1
          pad_device=$2   # SDL device string, or empty for keyboard-only
          pad_kbd=$3      # XInput2 device string, or empty for pad-only
          # Compose one control: pad ref, keyboard ref, or both ORed.
          bind() {
            if [ -n "$pad_device" ] && [ -n "$pad_kbd" ]; then
              printf '`%s` | `%s:%s`' "$1" "$pad_kbd" "$2"
            elif [ -n "$pad_device" ]; then
              printf '`%s`' "$1"
            else
              printf '`%s:%s`' "$pad_kbd" "$2"
            fi
          }
          printf '[%s]\n' "$pad_section"
          if [ -n "$pad_device" ]; then
            printf 'Device = %s\n' "$pad_device"
          else
            printf 'Device = %s\n' "$pad_kbd"
          fi
          printf 'Buttons/A = %s\n' "$(bind 'Button A' X)"
          printf 'Buttons/B = %s\n' "$(bind 'Button B' Z)"
          printf 'Buttons/X = %s\n' "$(bind 'Button X' C)"
          printf 'Buttons/Y = %s\n' "$(bind 'Button Y' S)"
          printf 'Buttons/Z = %s\n' "$(bind 'Shoulder R' D)"
          printf 'Buttons/Start = %s\n' "$(bind 'Start' Return)"
          printf 'Main Stick/Up = %s\n' "$(bind 'Left Y+' Up)"
          printf 'Main Stick/Down = %s\n' "$(bind 'Left Y-' Down)"
          printf 'Main Stick/Left = %s\n' "$(bind 'Left X-' Left)"
          printf 'Main Stick/Right = %s\n' "$(bind 'Left X+' Right)"
          printf 'Main Stick/Calibration = 100.00\n'
          printf 'C-Stick/Up = %s\n' "$(bind 'Right Y+' I)"
          printf 'C-Stick/Down = %s\n' "$(bind 'Right Y-' K)"
          printf 'C-Stick/Left = %s\n' "$(bind 'Right X-' J)"
          printf 'C-Stick/Right = %s\n' "$(bind 'Right X+' L)"
          printf 'C-Stick/Calibration = 100.00\n'
          printf 'Triggers/L = %s\n' "$(bind 'Trigger L' Q)"
          printf 'Triggers/R = %s\n' "$(bind 'Trigger R' W)"
          printf 'D-Pad/Up = %s\n' "$(bind 'Pad N' T)"
          printf 'D-Pad/Down = %s\n' "$(bind 'Pad S' G)"
          printf 'D-Pad/Left = %s\n' "$(bind 'Pad W' F)"
          printf 'D-Pad/Right = %s\n' "$(bind 'Pad E' H)"
          # Analog triggers and rumble exist only on a real pad.
          if [ -n "$pad_device" ]; then
            printf 'Triggers/L-Analog = `Trigger L`\n'
            printf 'Triggers/R-Analog = `Trigger R`\n'
            printf 'Rumble/Motor = `Motor L` | `Motor R`\n'
          fi
        }
        kbd_device="XInput2/0/Virtual core pointer"
        {
          if [ "$pad_count" -eq 0 ]; then
            # No pad: keyboard-only port 1, so the game is still playable.
            emit_pad "GCPad1" "" "$kbd_device"
          else
            pad_port=1
            printf '%s\n' "$pad_list" | while IFS="$(printf '\t')" read -r pad_index pad_name; do
              if [ -z "$pad_name" ] || [ "$pad_port" -gt 4 ]; then
                continue
              fi
              # Ports fill in listing order; the device index is SDL's own.
              if [ "$pad_port" -eq 1 ]; then
                emit_pad "GCPad1" "SDL/$pad_index/$pad_name" "$kbd_device"
              else
                emit_pad "GCPad$pad_port" "SDL/$pad_index/$pad_name" ""
              fi
              pad_port=$((pad_port + 1))
            done
          fi
        } > "$DOLPHIN_USER/Config/GCPadNew.ini"
      fi
    '';

    args = [
      "--user=$STROM_GAMEDIR/dolphin-user"
      "--batch"
      "--exec=${config.isoPath}"
    ];
  };
}
