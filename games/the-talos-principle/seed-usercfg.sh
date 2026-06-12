#!/bin/sh
# Seed Serious Engine 4's startup config so Talos launches on the Vulkan
# renderer instead of the default Direct3D 11.
#
# Why: under Proton/DXVK the default D3D11 backend fails to create a
# device at startup ("Cannot start Direct3D 11 device") and Talos.exe
# crashes while loading GfxD3D11.dll. The engine writes a startup marker
# (Temp/run.txt) it only clears on a clean exit, so every following
# launch reports "The game did not shut down successfully" and pops the
# modal "Do you want to start in safe mode?" dialog. Safe mode itself
# tries to set the renderer via the CONST cvar gfx_iAPI
# (Content/Shared/Config/SafeMode.cfg) and fails too -> infinite loop.
#
# The renderer is selected by the STRING cvar gfx_strAPI, NOT the const
# int gfx_iAPI. Talos.exe's own error text confirms it: "Wrong graphics
# API selected; going with default. (See 'gfx_strAPI' console variable.)"
# Valid values (from the binary): "VLK" (Vulkan), "D3D11", "D3D12".
# gfx_iAPI is a read-only value the engine derives from gfx_strAPI, which
# is why writing it from a cfg/cvar errors. Vulkan (DXVK passes it through
# to radv) is the renderer the whole Linux/Proton community runs Talos on.
#
# scr_strUserCfg defaults to "UserCfg.lua", resolved against the engine's
# working directory (the strom overlay root = $STROM_GAMEDIR). The engine
# auto-creates that template file on first run; if we don't seed it, the
# template carries no gfx setting and D3D11 is used. So seed the ROOT
# UserCfg.lua (the user-data dir passed as $1), not a Talos/ subdir.
#
# Seed only if our directive is absent, so a user who later tweaks the
# in-game graphics menu keeps their settings (the engine appends its own
# persisted cvars to this same file).

USERDATA="$1"
USERCFG="$USERDATA/UserCfg.lua"

mkdir -p "$USERDATA"

if ! grep -q 'gfx_strAPI' "$USERCFG" 2>/dev/null; then
  printf 'gfx_strAPI = "VLK";\n' >> "$USERCFG"
fi

# Clear the stale "did not shut down successfully" startup marker so the
# safe-mode dialog never fires (a prior D3D11 crash left it behind).
rm -f "$USERDATA/Temp/run.txt"
