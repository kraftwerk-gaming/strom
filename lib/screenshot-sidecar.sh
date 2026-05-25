# shellcheck shell=bash
# screenshot-sidecar fragment — sourced into the gamescope wrapper just
# before gamescope is exec'd, when STROM_AGENT_DEBUG is set or when the
# manual screenshot command needs to discover the active socket.
#
# Behaviour:
#   1. Spawn a background watcher that finds our gamescope process and
#      inspects its open file descriptors for the gamescope-N.lock it
#      flocks (gamescope writes its display name into that lock path).
#      Writes the socket name to $STROM_GAMEDIR/.strom-wayland-display
#      (consumed by the host-side `strom-screenshot` command).
#   2. When STROM_AGENT_DEBUG=1, capture a PNG every
#      STROM_AGENT_DEBUG_INTERVAL seconds (default 5) into
#      $STROM_GAMEDIR/screenshots/ until gamescope exits.
#   3. Install a trap that tears the watcher down on wrapper exit.
#
# Inputs (set by the surrounding gamescope wrapper before sourcing):
#   XDG_RUNTIME_DIR  - host runtime dir (passed through bwrap via /run bind)
#   STROM_GAMEDIR    - per-game state dir (exported by bwrap preHook)
# Optional:
#   STROM_AGENT_DEBUG            - "1" to enable the screenshot timer
#   STROM_AGENT_DEBUG_INTERVAL   - seconds between captures (default 5)

if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ -z "${STROM_GAMEDIR:-}" ]; then
  echo "strom-screenshot: XDG_RUNTIME_DIR or STROM_GAMEDIR unset; skipping sidecar" >&2
else
  __strom_shot_dir="$STROM_GAMEDIR/screenshots"
  __strom_shot_marker="$STROM_GAMEDIR/.strom-wayland-display"
  mkdir -p "$__strom_shot_dir"
  rm -f "$__strom_shot_marker"

  (
    set +e
    parent_pid=$$
    __strom_shot_log="$__strom_shot_dir/.sidecar.log"
    : > "$__strom_shot_log"
    {
      echo "[sidecar] start ppid=$parent_pid xdg=$XDG_RUNTIME_DIR"
    } >> "$__strom_shot_log" 2>&1

    # Find our gamescope child by walking the wrapper's descendants.
    # Identify by the gamescope-N.lock file it holds open. The wrapper
    # might `exec` into gamescope (same PID) OR keep gamescope as a
    # child (when a trap was installed, which prevents exec). Cover both.
    new_socket=""
    gs_pid=""
    for __strom_iter in $(seq 1 900); do
      if ! kill -0 "$parent_pid" 2>/dev/null; then
        echo "[sidecar] parent gone during socket discovery" >> "$__strom_shot_log"
        exit 0
      fi

      # Candidate PIDs: the wrapper itself (if it exec'd) plus any gamescope
      # descendants. We deliberately limit to processes sharing the
      # wrapper's session so we don't latch onto a concurrent strom game.
      candidates="$parent_pid"
      for child in $(pgrep -P "$parent_pid" 2>/dev/null); do
        candidates="$candidates $child"
      done

      for pid in $candidates; do
        [ -d "/proc/$pid" ] || continue
        # Skip non-gamescope cmdlines (the wrapper bash before exec).
        comm=$(cat "/proc/$pid/comm" 2>/dev/null) || comm=""
        case "$comm" in
          gamescope*) ;;
          *) continue ;;
        esac
        for fd in /proc/"$pid"/fd/*; do
          target=$(readlink "$fd" 2>/dev/null) || continue
          case "$target" in
            "$XDG_RUNTIME_DIR"/gamescope-[0-9]*.lock)
              # Strip leading dir and trailing .lock.
              name=${target##*/}
              name=${name%.lock}
              # Skip *-ei.lock (libei companion, not the wayland display).
              case "$name" in
                *-ei) continue ;;
              esac
              new_socket="$name"
              gs_pid="$pid"
              break 2
              ;;
          esac
        done
      done

      [ -n "$new_socket" ] && break
      sleep 0.1
    done

    if [ -z "$new_socket" ]; then
      echo "[sidecar] no gamescope lock fd found within 90s" >> "$__strom_shot_log"
      echo "strom-screenshot: no gamescope socket found within 90s" >&2
      exit 0
    fi

    # Wait for the socket file itself to be ready (gamescope creates the
    # .lock first, then the socket).
    for _ in $(seq 1 50); do
      [ -S "$XDG_RUNTIME_DIR/$new_socket" ] && break
      sleep 0.1
    done

    echo "[sidecar] detected socket=$new_socket gs_pid=$gs_pid after ${__strom_iter} polls" >> "$__strom_shot_log"
    printf '%s\n' "$new_socket" > "$__strom_shot_marker"

    if [ "${STROM_AGENT_DEBUG:-0}" != "1" ]; then
      # Marker-only mode: the host `strom-screenshot` command will take
      # the actual captures on demand. Nothing more to do here.
      exit 0
    fi

    interval="${STROM_AGENT_DEBUG_INTERVAL:-5}"
    n=0
    while kill -0 "$parent_pid" 2>/dev/null; do
      n=$((n + 1))
      out="$__strom_shot_dir/screenshot-$(date -u +%Y%m%dT%H%M%SZ)-$n.png"
      # gamescopectl talks to its parent gamescope via gamescope_control
      # protocol over WAYLAND_DISPLAY. Gamescope writes the PNG itself
      # (it has framebuffer access; wlr-screencopy is not advertised on
      # the nested socket, so external tools like grim cannot work).
      if WAYLAND_DISPLAY="$new_socket" gamescopectl screenshot "$out" >>"$__strom_shot_log" 2>&1; then
        echo "[sidecar] captured $out" >> "$__strom_shot_log"
      fi
      sleep "$interval"
    done
    echo "[sidecar] parent gone; exiting after $n captures" >> "$__strom_shot_log"
  ) &
  __strom_shot_pid=$!

  __strom_shot_prev_trap=$(trap -p EXIT INT TERM | sed -n "s/^trap -- '\\(.*\\)' EXIT$/\\1/p" | head -n1)
  # shellcheck disable=SC2064 # expansion-now is intentional.
  trap "kill -TERM $__strom_shot_pid 2>/dev/null || true; ${__strom_shot_prev_trap:-true}" EXIT INT TERM
fi
