#!/bin/sh
# Seed HKLM\Software\TopWare\Earth 2150\BaseGame\FileSystem in the
# wineprefix system.reg. Earth2150.exe self-validates its install at
# startup by reading this key's DataPath/OutputDir values; in a fresh
# Proton prefix the key is absent, so the engine aborts with the modal
# "Earth 2150 isn't properly installed. Please reinstall program."
# dialog before reaching the menu.
#
# Verified by a WINEDEBUG=+reg trace of the failing launch: the engine
# issues exactly one lookup,
#   NtOpenKeyEx(\Registry\Machine, "Software\TopWare\Earth 2150\BaseGame\FileSystem")
# which returns nil. \Registry\Machine is HKLM, so the key lives in
# system.reg, not user.reg. Earth2150.exe is 32-bit, so wine's WOW64
# redirector rewrites its HKLM\Software lookups to
# HKLM\Software\Wow6432Node; seed both the redirected (Wow6432Node) and
# plain paths so the lookup resolves regardless.
#
# Reality Pump's file system uses a search-path syntax where each entry
# is a directory followed by the "/>" recurse marker, ";"-separated.
# DataPath points the engine at the game tree; OutputDir is the same
# directory (config/savegames land next to the binary in the overlay
# upper). The game lives at $GAMEDIR (the overlay mount), and drive Z:
# maps to /, so the Windows path is Z:\<GAMEDIR>.
#
# Idempotent: strips any prior FileSystem block before re-emitting, so
# a path change between runs cannot leave a stale entry.

SYSREG="$1"
# Unix path of the in-prefix game tree, e.g. /tmp/.strom-overlay.
GAMEDIR_UNIX="$2"

# Convert the Unix path to a Windows path on drive Z: with the
# backslashes doubled, as wine's text registry requires in string
# values: /tmp/.strom-overlay -> Z:\\tmp\\.strom-overlay (which wine
# reads back as Z:\tmp\.strom-overlay).
GAMEDIR_WIN="Z:$(printf '%s' "$GAMEDIR_UNIX" | sed 's|/|\\\\|g')"
# Escape once more for sed's replacement text (\ -> \\).
SED_WIN=$(printf '%s' "$GAMEDIR_WIN" | sed 's|\\|\\\\|g')

seed_block() {
  # $1: section header body as written on disk (backslashes already
  # doubled, e.g. Software\\Wow6432Node\\TopWare\\Earth 2150\\...).
  # $2: a basic-regex matching that header for the idempotent strip
  # (each on-disk \\ becomes \\\\ in BRE).
  header="$1"
  strip_re="$2"

  if grep -q "$strip_re" "$SYSREG"; then
    sed -i "/^\\[${strip_re}\\]/,/^\$/d" "$SYSREG"
  fi

  {
    printf '\n[%s] 1700000000\n' "$header"
    printf '"DataPath"="@WINPATH@/>"\n'
    printf '"OutputDir"="@WINPATH@"\n'
  } >> "$SYSREG"
}

seed_block \
  'Software\\Wow6432Node\\TopWare\\Earth 2150\\BaseGame\\FileSystem' \
  'Software\\\\Wow6432Node\\\\TopWare\\\\Earth 2150\\\\BaseGame\\\\FileSystem'
seed_block \
  'Software\\TopWare\\Earth 2150\\BaseGame\\FileSystem' \
  'Software\\\\TopWare\\\\Earth 2150\\\\BaseGame\\\\FileSystem'

# Substitute the install path last so its own backslashes never collide
# with the s/// syntax in seed_block's strip step.
sed -i "s|@WINPATH@|${SED_WIN}|g" "$SYSREG"
