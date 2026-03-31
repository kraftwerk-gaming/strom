#!/bin/sh
# Inject RA2 registry keys into Wine prefix system.reg
SYSREG="$1"
GAMEDIR="$2"

WINEPATH='Z:'"$(echo "$GAMEDIR" | sed 's|/|\\\\|g')"'\\\\'

cat >> "$SYSREG" <<EOF

[Software\\\\Westwood\\\\Red Alert 2]
"InstallPath"="$WINEPATH"
"Serial"="0"
"SKU"=dword:00000801
"Version"=dword:00010006
"Language"="English"

[Software\\\\Westwood\\\\Yuri's Revenge]
"InstallPath"="$WINEPATH"
"Serial"="0"
"SKU"=dword:00000901
"Version"=dword:00010001
"Language"="English"
EOF
