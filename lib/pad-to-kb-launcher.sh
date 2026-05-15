# shellcheck shell=bash
# pad-to-kb launcher fragment — sourced into bwrap.preHook when
# padToKb.enable = true. Starts the evsieve remapper in the background,
# captures its PID, and installs traps so the synthesized uinput device
# is torn down with the game.
#
# Inputs (set in the surrounding scope before this fragment runs):
#   STROM_PAD_TO_KB_EVSIEVE        - path to the evsieve binary
#   STROM_PAD_TO_KB_DEVICE_GLOBS   - space-separated glob patterns or
#                                    literal paths for --input
#   STROM_PAD_TO_KB_MAPPING_ARGS   - bash array (declared in caller)
#                                    of the rendered evsieve argv
#                                    (bindings + --output)
#   STROM_CACHEDIR                 - per-game cache dir (already created)
#
# Exports (consumed downstream + visible to bwrap):
#   STROM_PAD_TO_KB_LINK           - symlink to the synthesized event
#                                    device (evsieve creates+removes)
#   STROM_PAD_TO_KB_PID            - background PID for the EXIT trap

STROM_PAD_TO_KB_LINK="$STROM_CACHEDIR/virtual-keyboard"
export STROM_PAD_TO_KB_LINK

# Best-effort sanity check — warn loud but don't abort the launch if
# /dev/uinput is missing or unwritable. The game may still work as a
# normal pad-only experience and the user can act on the warning.
if [ ! -w /dev/uinput ]; then
  echo "pad-to-kb: /dev/uinput is not writable by $(id -un); skipping remapper" >&2
  echo "pad-to-kb: add the user to the 'input' group and ensure NixOS has uinput access enabled" >&2
else
  # Expand the device globs against the live host filesystem. Use
  # nullglob so non-matching patterns vanish instead of being passed
  # literally to evsieve (which would refuse to start).
  __strom_input_args=()
  __strom_old_nullglob=$(shopt -p nullglob || true)
  shopt -s nullglob
  # shellcheck disable=SC2086 # word-splitting the glob list is intentional.
  for __strom_dev in $STROM_PAD_TO_KB_DEVICE_GLOBS; do
    __strom_input_args+=(--input "$__strom_dev" persist=reopen)
  done
  eval "$__strom_old_nullglob"

  if [ "${#__strom_input_args[@]}" -eq 0 ]; then
    echo "pad-to-kb: no input device matched [$STROM_PAD_TO_KB_DEVICE_GLOBS]; skipping remapper" >&2
  else
    "$STROM_PAD_TO_KB_EVSIEVE" \
      "${__strom_input_args[@]}" \
      "${STROM_PAD_TO_KB_MAPPING_ARGS[@]}" \
      --output \
      "create-link=$STROM_PAD_TO_KB_LINK" \
      "name=$STROM_PAD_TO_KB_VIRTUAL_NAME" >&2 &
    STROM_PAD_TO_KB_PID=$!
    export STROM_PAD_TO_KB_PID

    # Wait briefly for evsieve to create the virtual device.
    # evsieve typically takes <50ms to call ioctl(UI_DEV_CREATE);
    # 1s with a 50ms polling interval is generous and bounded.
    for _ in $(seq 1 20); do
      if [ -e "$STROM_PAD_TO_KB_LINK" ]; then break; fi
      sleep 0.05
    done
    if [ ! -e "$STROM_PAD_TO_KB_LINK" ]; then
      echo "pad-to-kb: evsieve did not create $STROM_PAD_TO_KB_LINK within 1s (continuing anyway)" >&2
    fi

    # Append to any existing EXIT trap installed by an earlier
    # preHook fragment (e.g. fuse-overlayfs's fusermount cleanup).
    __strom_prev_trap=$(trap -p EXIT INT TERM | sed -n "s/^trap -- '\\(.*\\)' EXIT$/\\1/p" | head -n1)
    # shellcheck disable=SC2064 # expansion-now is intentional: PID + prior trap text must be captured.
    trap "kill -TERM $STROM_PAD_TO_KB_PID 2>/dev/null || true; ${__strom_prev_trap:-true}" EXIT INT TERM
  fi
fi
