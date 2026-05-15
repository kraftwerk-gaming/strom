#!/bin/sh
# Seed HKCU\Software\Bethesda Softworks\Call Of Cthulhu DCoTE\Settings\
# in the wineprefix user.reg. CoCMainWin32.exe checks these keys at
# startup; when missing or partially populated it spawns the bundled
# CoCDCoTELauncher.exe — a settings-only dialog that writes the keys
# then exits without starting the game. Under Proton's
# waitforexitandrun the wineprefix goes empty after that exit and the
# whole session tears down, which the user sees as "press Launch, game
# quits".
#
# Values mirror what the launcher writes when picking 1920x1080 60 Hz
# fullscreen with no AA. Resolution numbers are decimal DWORDs encoded
# as hex per .reg syntax (1920 = 0x780, 1080 = 0x438, 60 = 0x3c,
# 32 = 0x20). VideoModeSet=1 is the sentinel the launcher sets to
# signal "settings are valid"; the game refuses to skip the launcher
# without it.

USERREG="$1"

# Strip any existing Bethesda block (including the launcher's empty
# Executable=hex(1): scrap, which can trip the launcher fallback) and
# re-emit a complete set every preRun. sed range from the section
# header through to the blank line that closes it.
if grep -q 'Bethesda Softworks\\\\Call Of Cthulhu DCoTE\\\\Settings' "$USERREG"; then
  sed -i '/^\[Software\\\\Bethesda Softworks\\\\Call Of Cthulhu DCoTE\\\\Settings\]/,/^$/d' "$USERREG"
fi

cat >> "$USERREG" <<'EOF'

[Software\\Bethesda Softworks\\Call Of Cthulhu DCoTE\\Settings] 1700000000
"ActivateSubtitles"=dword:00000002
"Adapter"=dword:00000000
"AdapterName"="\\\\.\\DISPLAY1"
"AntiAlias"=dword:00000000
"Antialiasing Mode"=dword:00000000
"Display Adapter"=dword:00000000
"Display Mode"=dword:00000000
"FullScreen"=dword:00000001
"FullScreenBitDepth"=dword:00000020
"FullScreenHeight"=dword:00000438
"FullScreenWidth"=dword:00000780
"Language"="English"
"MultisampleMode"=dword:00000000
"RefreshRate"=dword:0000003c
"ScreenHeight"=dword:00000438
"ScreenWidth"=dword:00000780
"VideoModeSet"=dword:00000001
"WinWindowed"=dword:00000000
"WindowHeight"=dword:00000438
"WindowWidth"=dword:00000780
"WindowXPos"=dword:00000000
"WindowYPos"=dword:00000000
EOF
