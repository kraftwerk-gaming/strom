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

      # Pre-seed GCPadNew.ini for every detected pad, mirroring Dolphin's
      # bundled "SDL Gamepad" profile. Port 1 additionally carries the
      # keyboard fallback (Dolphin's own Linux defaults) so a padless
      # install is still playable; ports 2-4 are pad-only, since sharing
      # one keyboard across four players is meaningless. Without this
      # Dolphin auto-binds keyboard to port 1 only and every extra player
      # has to be assigned by hand in Options → Controllers.
      # Seed when there is nothing to preserve. "Write-if-absent" alone is
      # not enough: if the very first launch happens with no pad attached,
      # Dolphin writes its own keyboard-only GCPadNew.ini on exit, and a
      # file-exists gate would then skip pad seeding forever on that
      # install even after a pad is plugged in. So also seed when the file
      # binds no SDL device at all. A user who has mapped a pad (or remapped
      # one) has `Device = SDL/` lines and is never touched.
      needs_pad_seed=0
      if [ "$pad_count" -gt 0 ]; then
        if ! [ -f "$DOLPHIN_USER/Config/GCPadNew.ini" ]; then
          needs_pad_seed=1
        elif ! ${config.pkgs.gnugrep}/bin/grep -q 'Device = SDL/' "$DOLPHIN_USER/Config/GCPadNew.ini"; then
          needs_pad_seed=1
        fi
      fi
      if [ "$needs_pad_seed" -eq 1 ]; then
        # shellcheck disable=SC2016 # Dolphin's INI syntax wraps every control
        # reference in literal backticks, so these printf formats must stay
        # single-quoted; nothing in them is meant to expand.
        emit_pad() {
          pad_section=$1
          pad_device=$2
          pad_kbd=$3
          # Second binding on a control, only when a keyboard fallback applies.
          alt() {
            if [ -n "$pad_kbd" ]; then
              printf ' | `%s:%s`' "$pad_kbd" "$1"
            fi
          }
          printf '[%s]\n' "$pad_section"
          printf 'Device = %s\n' "$pad_device"
          printf 'Buttons/A = `Button A`%s\n' "$(alt X)"
          printf 'Buttons/B = `Button B`%s\n' "$(alt Z)"
          printf 'Buttons/X = `Button X`%s\n' "$(alt C)"
          printf 'Buttons/Y = `Button Y`%s\n' "$(alt S)"
          printf 'Buttons/Z = `Shoulder R`%s\n' "$(alt D)"
          printf 'Buttons/Start = `Start`%s\n' "$(alt Return)"
          printf 'Main Stick/Up = `Left Y+`%s\n' "$(alt Up)"
          printf 'Main Stick/Down = `Left Y-`%s\n' "$(alt Down)"
          printf 'Main Stick/Left = `Left X-`%s\n' "$(alt Left)"
          printf 'Main Stick/Right = `Left X+`%s\n' "$(alt Right)"
          printf 'Main Stick/Calibration = 100.00\n'
          printf 'C-Stick/Up = `Right Y+`%s\n' "$(alt I)"
          printf 'C-Stick/Down = `Right Y-`%s\n' "$(alt K)"
          printf 'C-Stick/Left = `Right X-`%s\n' "$(alt J)"
          printf 'C-Stick/Right = `Right X+`%s\n' "$(alt L)"
          printf 'C-Stick/Calibration = 100.00\n'
          printf 'Triggers/L = `Trigger L`%s\n' "$(alt Q)"
          printf 'Triggers/R = `Trigger R`%s\n' "$(alt W)"
          printf 'Triggers/L-Analog = `Trigger L`\n'
          printf 'Triggers/R-Analog = `Trigger R`\n'
          printf 'D-Pad/Up = `Pad N`%s\n' "$(alt T)"
          printf 'D-Pad/Down = `Pad S`%s\n' "$(alt G)"
          printf 'D-Pad/Left = `Pad W`%s\n' "$(alt F)"
          printf 'D-Pad/Right = `Pad E`%s\n' "$(alt H)"
          printf 'Rumble/Motor = `Motor L` | `Motor R`\n'
        }
        {
          pad_port=1
          printf '%s\n' "$pad_list" | while IFS="$(printf '\t')" read -r pad_index pad_name; do
            if [ -z "$pad_name" ] || [ "$pad_port" -gt 4 ]; then
              continue
            fi
            # Ports fill in listing order; the device index is SDL's own.
            if [ "$pad_port" -eq 1 ]; then
              emit_pad "GCPad1" "SDL/$pad_index/$pad_name" "XInput2/0/Virtual core pointer"
            else
              emit_pad "GCPad$pad_port" "SDL/$pad_index/$pad_name" ""
            fi
            pad_port=$((pad_port + 1))
          done
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
