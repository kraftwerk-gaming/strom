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
            # Seeding runs when there is nothing worth preserving:
            #   - no file yet;
            #   - a pad is now attached but the file binds no SDL device (the
            #     first launch happened padless);
            #   - the file binds an SDL device that is NOT currently attached.
            # That last case is what bit pikmin-2: a pad present at first launch
            # (here a virtual one used for verification) is baked into `Device =`,
            # and once it disappears Dolphin has a section pointing at a device
            # that no longer exists. Reseeding restores working input instead of
            # leaving the install permanently dead. A user whose mapped pad is
            # simply attached is never touched.
            needs_pad_seed=0
            gcpad_ini="$DOLPHIN_USER/Config/GCPadNew.ini"
            if ! [ -f "$gcpad_ini" ]; then
              needs_pad_seed=1
            elif [ "$pad_count" -gt 0 ] \
              && ! ${config.pkgs.gnugrep}/bin/grep -q 'Device = SDL/' "$gcpad_ini"; then
              needs_pad_seed=1
            else
              # Every SDL device the file references must still be attached.
              while IFS= read -r dev; do
                [ -n "$dev" ] || continue
                if ! printf '%s\n' "$pad_list" \
                  | ${config.pkgs.gawk}/bin/awk -F'\t' -v d="$dev" '$1 != "" && ("SDL/" $1 "/" $2) == d { found = 1 } END { exit !found }'; then
                  needs_pad_seed=1
                fi
              done <<EOF
      $(${config.pkgs.gnused}/bin/sed -n 's/^Device = \(SDL\/.*\)$/\1/p' "$gcpad_ini")
      EOF
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
                #
                # When a pad is present it IS player 1: the section's Device is
                # the pad, so Dolphin's own controller UI shows the gamepad on
                # port 1, and the keyboard rides along as a fully-qualified
                # second binding ("XInput2/0/Virtual core pointer:X"). With no
                # pad the keyboard becomes the Device instead, so a padless
                # machine is still playable. A pad that later disappears is
                # handled by the reseed rule above rather than by demoting the
                # pad here.
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

            # Pre-seed WiimoteNew.ini the same way, so a Wii disc is playable
            # from a pad instead of only from a desk. Dolphin's stock emulated
            # Wiimote binds keyboard+mouse only (verified against upstream
            # LoadDefaults: A/B are `Click 1`/`Click 3`, shake is `Click 2`,
            # pointing is `Cursor X/Y`, the Nunchuk stick is WASD), which is
            # enough to play at a desk and leaves a pad-only couch seat able to
            # boot a Wii game and not play it -- exactly what
            # games/super-mario-galaxy documented as its open gap.
            #
            # Inert for GameCube titles: Dolphin only consults this file for
            # Wii discs, so seeding it unconditionally costs a GC game nothing
            # and means no per-game knob has to be set correctly.
            #
            # Reseed rules and the pad/keyboard layering are identical to
            # GCPadNew.ini above, including the "mapped pad is gone" case.
            needs_wii_seed=0
            wiimote_ini="$DOLPHIN_USER/Config/WiimoteNew.ini"
            if ! [ -f "$wiimote_ini" ]; then
              needs_wii_seed=1
            elif [ "$pad_count" -gt 0 ] \
              && ! ${config.pkgs.gnugrep}/bin/grep -q 'Device = SDL/' "$wiimote_ini"; then
              needs_wii_seed=1
            else
              while IFS= read -r dev; do
                [ -n "$dev" ] || continue
                if ! printf '%s\n' "$pad_list" \
                  | ${config.pkgs.gawk}/bin/awk -F'\t' -v d="$dev" '$1 != "" && ("SDL/" $1 "/" $2) == d { found = 1 } END { exit !found }'; then
                  needs_wii_seed=1
                fi
              done <<EOF
      $(${config.pkgs.gnused}/bin/sed -n 's/^Device = \(SDL\/.*\)$/\1/p' "$wiimote_ini")
      EOF
            fi
            if [ "$needs_wii_seed" -eq 1 ]; then
              # shellcheck disable=SC2016 # Dolphin control references are literal
              # backticks; these formats must stay single-quoted.
              emit_wiimote() {
                wm_section=$1
                wm_device=$2   # SDL device string, or empty for keyboard-only
                wm_kbd=$3      # XInput2 device string, or empty for pad-only
                wbind() {
                  if [ -n "$wm_device" ] && [ -n "$wm_kbd" ]; then
                    printf '`%s` | `%s:%s`' "$1" "$wm_kbd" "$2"
                  elif [ -n "$wm_device" ]; then
                    printf '`%s`' "$1"
                  else
                    printf '`%s:%s`' "$wm_kbd" "$2"
                  fi
                }
                printf '[%s]\n' "$wm_section"
                if [ -n "$wm_device" ]; then
                  printf 'Device = %s\n' "$wm_device"
                else
                  printf 'Device = %s\n' "$wm_kbd"
                fi
                # Source 1 = emulated. Only slots that have something driving
                # them are enabled; a slot switched on with nothing bound shows
                # the game a connected-but-dead remote.
                printf 'Source = 1\n'
                # A jumps, B is the trigger (shoot). Spin -- the move Galaxy
                # asks for constantly -- is a shake, so it gets two comfortable
                # bindings rather than a buried one.
                printf 'Buttons/A = %s\n' "$(wbind 'Button A' 'Click 1')"
                printf 'Buttons/B = %s\n' "$(wbind 'Button B' 'Click 3')"
                printf 'Buttons/1 = %s\n' "$(wbind 'Button Y' 1)"
                printf 'Buttons/2 = %s\n' "$(wbind 'Button X' 2)"
                printf 'Buttons/- = %s\n' "$(wbind 'Back' Q)"
                printf 'Buttons/+ = %s\n' "$(wbind 'Start' E)"
                printf 'Buttons/Home = %s\n' "$(wbind 'Guide' Return)"
                printf 'D-Pad/Up = %s\n' "$(wbind 'Pad N' Up)"
                printf 'D-Pad/Down = %s\n' "$(wbind 'Pad S' Down)"
                printf 'D-Pad/Left = %s\n' "$(wbind 'Pad W' Left)"
                printf 'D-Pad/Right = %s\n' "$(wbind 'Pad E' Right)"
                # Pointing: right stick, ABSOLUTE (stick centre = screen
                # centre, release re-centres the pointer). Deliberately not
                # `IR/Relative Input = True`: that setting is per-remote and
                # would make the mouse relative too, breaking the desk map that
                # was verified in game on this title.
                printf 'IR/Up = %s\n' "$(wbind 'Right Y+' 'Cursor Y-')"
                printf 'IR/Down = %s\n' "$(wbind 'Right Y-' 'Cursor Y+')"
                printf 'IR/Left = %s\n' "$(wbind 'Right X-' 'Cursor X-')"
                printf 'IR/Right = %s\n' "$(wbind 'Right X+' 'Cursor X+')"
                # Spin attack.
                for wm_axis in X Y Z; do
                  printf 'Shake/%s = %s\n' "$wm_axis" "$(wbind 'Shoulder R' 'Click 2')"
                done
                printf 'Extension = Nunchuk\n'
                printf 'Nunchuk/Buttons/C = %s\n' "$(wbind 'Shoulder L' Control_L)"
                printf 'Nunchuk/Buttons/Z = %s\n' "$(wbind 'Trigger L' Shift_L)"
                printf 'Nunchuk/Stick/Up = %s\n' "$(wbind 'Left Y+' W)"
                printf 'Nunchuk/Stick/Down = %s\n' "$(wbind 'Left Y-' S)"
                printf 'Nunchuk/Stick/Left = %s\n' "$(wbind 'Left X-' A)"
                printf 'Nunchuk/Stick/Right = %s\n' "$(wbind 'Left X+' D)"
                printf 'Nunchuk/Stick/Calibration = 100.00\n'
                # Nunchuk shake is its own control (some games use it for a
                # second spin); mirror the remote's.
                for wm_axis in X Y Z; do
                  printf 'Nunchuk/Shake/%s = %s\n' "$wm_axis" "$(wbind 'Trigger R' 'Click 2')"
                done
                if [ -n "$wm_device" ]; then
                  printf 'Rumble/Motor = `Motor L` | `Motor R`\n'
                fi
              }
              {
                if [ "$pad_count" -eq 0 ]; then
                  emit_wiimote "Wiimote1" "" "$kbd_device"
                else
                  wm_port=1
                  printf '%s\n' "$pad_list" | while IFS="$(printf '\t')" read -r pad_index pad_name; do
                    if [ -z "$pad_name" ] || [ "$wm_port" -gt 4 ]; then
                      continue
                    fi
                    if [ "$wm_port" -eq 1 ]; then
                      emit_wiimote "Wiimote1" "SDL/$pad_index/$pad_name" "$kbd_device"
                    else
                      emit_wiimote "Wiimote$wm_port" "SDL/$pad_index/$pad_name" ""
                    fi
                    wm_port=$((wm_port + 1))
                  done
                fi
                # Balance Board slot: Dolphin expects the section to exist.
                printf '[BalanceBoard]\nSource = 0\n'
              } > "$wiimote_ini"
            fi
    '';

    args = [
      "--user=$STROM_GAMEDIR/dolphin-user"
      "--batch"
      "--exec=${config.isoPath}"
    ];
  };
}
