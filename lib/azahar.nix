# azahar wrapperModule (raw module source).
#
# Wraps Azahar for Nintendo 3DS emulation. The wrapped binary IS azahar;
# the ROM path is a typed option (romPath) passed as its one positional
# argument -- `azahar [options] <file path>`, which is the whole CLI
# contract for launching content.
#
# Azahar is the surviving 3DS emulator: Citra was deleted after the 2024
# Nintendo settlement and Lime3DS merged into Azahar and archived itself in
# April 2025.
#
# Its user data follows the XDG spec on Linux (src/common/file_util.cpp
# GetUserDirectory reads XDG_DATA_HOME / XDG_CONFIG_HOME / XDG_CACHE_HOME),
# so pointing those at $STROM_GAMEDIR keeps saves, save states and the
# emulated NAND with the game instead of in the user's global
# ~/.local/share. That is the same shape lib/dolphin.nix gets from
# --user=, reached differently because Azahar has no such flag.
#
# There is deliberately no config seeding here. Azahar owns its ini at
# runtime and rewrites it on exit, and unlike Dolphin it needs nothing
# seeded to be playable: the AES keys a retail dump needs are compiled into
# the binary (CMake ENABLE_BUILTIN_KEYBLOB, default ON), so a decrypted
# dump boots with no system files at all.
#
# Usage as a sub-option submodule:
#   lib.types.submoduleWith {
#     specialArgs = { inherit wlib; };
#     modules = [ wlib.modules.wrapper wlib.modules.meta (import ./azahar.nix) ];
#   }
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  _class = "wrapper";

  options = {
    romPath = mkOption {
      type = types.str;
      description = ''
        Path to the 3DS dump. May contain shell variables (e.g.
        $STROM_OVERLAY/foo.3ds). Azahar boots .3ds, .cci, .cxi, .app,
        .3dsx and .cia, plus its own zstd-compressed .zcci / .zcxi /
        .zcia / .z3dsx (src/core/loader/loader.cpp).

        It must be a DECRYPTED dump. An encrypted one is rejected outright
        with "Azahar does not support encrypted applications", because
        decrypting needs per-console keys that only a real 3DS has. Prefer
        .3ds / .cci: a .cia is an installable package that wants
        installing into the emulated NAND rather than booting directly.
      '';
    };

    fullscreen = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Start Azahar fullscreen. On by default because the game is already
        nested inside gamescope, whose surface is the whole screen; a
        windowed emulator inside it just wastes the panel.
      '';
    };
  };

  config = {
    package = config.pkgs.azahar;
    exePath = "${config.pkgs.azahar}/bin/azahar";
    binName = lib.mkDefault "azahar";

    env = {
      # Azahar is Qt6, and this tree runs its Qt emulators on gamescope's
      # nested Xwayland (lib/dolphin.nix, lib/pcsx2.nix, lib/retroarch.nix
      # all force an X11 backend, each for its own measured reason). This
      # one is convention rather than a diagnosis: no wayland-specific
      # fault has been observed in Azahar here, and it is set to keep the
      # couch stack uniform rather than to work around something known.
      QT_QPA_PLATFORM = "xcb";
    };

    preHook = ''
      # Same reason as QT_QPA_PLATFORM: keep Qt off the wayland display.
      unset WAYLAND_DISPLAY

      # Per-game user data. Azahar resolves every one of its directories
      # from these three, so a prefix wipe or a shared home cannot take a
      # save with it, and two games never share an emulated NAND.
      export XDG_DATA_HOME="$STROM_GAMEDIR/azahar/data"
      export XDG_CONFIG_HOME="$STROM_GAMEDIR/azahar/config"
      export XDG_CACHE_HOME="$STROM_GAMEDIR/azahar/cache"
      mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    '';

    args = lib.optional config.fullscreen "--fullscreen" ++ [ config.romPath ];
  };
}
