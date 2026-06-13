{
  self,
  lib,
  pkgs,
  fetchIpfs,
  _7zz,
}:

let
  # UnderRail (Stygian Software 2015), an isometric turn-based RPG built on
  # Microsoft XNA / .NET Framework. Source: Underrail.v1.3.0.15-P2P.zip,
  # a pre-installed Steam release (TENOKE crack) from Skidrow Reloaded
  # (pixeldrain u/VTkXg6ja, 14.9 GiB). The zip contains a single top-level
  # directory Underrail.v1.3.0.15-P2P/ with underrail.exe + data/ trees at
  # the root. _CommonRedist/ (DirectX redistributables) is removed at build
  # time; the TENOKE Steam crack (steam_api.dll + tenoke.ini) is kept intact
  # as Proton expects a steam_api.dll to be present for XNA/.NET init.
  src = fetchIpfs {
    cid = "QmVoaY6jTJWyrv9jHAUDXQ3NPrQjFmuFWbtLSBYSZnSe4h";
    fallbackUrl = "https://pixeldrain.com/u/VTkXg6ja";
    hash = "sha256-B3HnD3fSsEpIu4XrHvI9v9kIQceH9Uf7h506G48Bv6A=";
    name = "Underrail.v1.3.0.15-P2P.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "underrail";

  inherit src;

  nativeBuildInputs = [
    _7zz
  ];

  # Pre-installed P2P zip layout: Underrail.v1.3.0.15-P2P/underrail.exe
  # plus data/ trees and DLL dependencies at the same level.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/extract"
    7zz x -bso0 -bsp0 -o"$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/Underrail.v1.3.0.15-P2P/. "$out"/
    rm -rf "$out/_CommonRedist"
    rm -f "$out/SKIDROWRELOADED.COM.txt"
  '';

  runtime = "proton";

  executable = "underrail.exe";

  # White horizontal lines across floor tiles are caused by UnderRail's
  # in-game "Shader Mode = Advanced" video option (the default), not by the
  # graphics backend — both DXVK and wined3d show the seams with Advanced,
  # and both are clean with "Legacy". (PROTON_USE_WINED3D was tried here and
  # did NOT fix the lines; it only cost perf, so it is gone.) The shader mode
  # lives in UnderRail's binary config.dat (a 16-byte checksum + 8-byte header
  # + GZIP'd .NET-serialized settings), which is guarded by that checksum, so
  # byte-patching a field in place fails validation. Instead we seed a
  # known-good config.dat whose shader mode is already Legacy on first launch
  # (see preRun); existing players keep their own config untouched.
  #
  # config.dat carries default settings only (resolution / audio / keybinds /
  # shader mode), NOT save data — saves live in UnderRail/Saves/. Seeding it
  # therefore only sets fresh-install defaults.

  # XNA/.NET game: persists its config and saves under the Windows user
  # profile (Documents\\My Games\\UnderRail, relocated to
  # $STROM_GAMEDIR/UnderRail). Relocate the tree so prefix wipes keep saved
  # games and characters.
  saveLocations = [
    "Documents/My Games/UnderRail"
  ];

  # Seed the Legacy-shader config.dat the first time, writing straight to the
  # saveLocation target ($STROM_GAMEDIR/UnderRail) so it survives prefix
  # wipes and is picked up through the relocation symlink. Guard on absence so
  # players who already have a config.dat (with their own settings) keep it.
  preRun = ''
    underrail_cfg="$STROM_GAMEDIR/UnderRail/config.dat"
    if [ ! -e "$underrail_cfg" ]; then
      mkdir -p "$STROM_GAMEDIR/UnderRail"
      install -m 0644 ${./config-legacy.dat} "$underrail_cfg"
    fi
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "UnderRail (Stygian Software 2015, v1.3.0.15 P2P, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "underrail";
  };
}
