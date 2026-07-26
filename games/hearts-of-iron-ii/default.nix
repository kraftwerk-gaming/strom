{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unshield,
}:

let
  # Hearts of Iron II: Doomsday (2005/2006 Paradox), English retail CD image
  # (archive.org item "hoi2_20230112", "HoI2 Collection.iso"). The ISO holds
  # three InstallShield 6 installers side by side; we package the Doomsday
  # standalone (the definitive HoI2 generation). Its game files extract
  # statically from the InstallShield cabinets with `unshield` -- no installer,
  # serial or CD required (25650/25650 files, zero errors). Unlike the base
  # hoi2/ disc, the Doomsday HoI2.exe carries no CD / copy-protection check.
  src = fetchIpfs {
    cid = "QmaWN3QaRb15tr5K21Ze8YdkQsBcFNbhKmACFhzqCb6XCA";
    fallbackUrl = "https://archive.org/download/hoi2_20230112/HoI2%20Collection.iso";
    hash = "sha256-tlrKlSnCELkiZLP/ACoTsLnW5cL3sCYdFeN7Cw4m+S0=";
    name = "hearts-of-iron-ii.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hearts-of-iron-ii";

  inherit src;

  nativeBuildInputs = [
    p7zip
    unshield
  ];

  # Static extraction -- no InstallShield engine, serial, or CD:
  #   1. 7z pulls the Doomsday installer (data1.hdr + data1.cab + data2.cab)
  #      out of the ISO.
  #   2. unshield extracts the cabinets. Files land under installer file-group
  #      names; the whole game (HoI2.exe + db/ gfx/ map/ scenarios/ config/ ...)
  #      lives under the "common" group, which IS the install root.
  #   3. The tiny _Engine_*/_Support_* groups are InstallShield runtime
  #      artifacts (iKernel.exe etc.), not game files -- left behind.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/inst" "$TMPDIR/game"
    7z x -y -o"$TMPDIR/inst" "$src" \
      "doomsday/data1.hdr" "doomsday/data1.cab" "doomsday/data2.cab" >/dev/null
    unshield -d "$TMPDIR/game" x "$TMPDIR/inst/doomsday/data1.hdr" >/dev/null
    cp -r "$TMPDIR/game/common"/. "$out"/
    # The shipped default settings.cfg is its own file-group; seed it if the
    # game root doesn't already carry one.
    if [ -f "$TMPDIR/game/english/settings.cfg" ] && [ ! -e "$out/settings.cfg" ]; then
      cp "$TMPDIR/game/english/settings.cfg" "$out/settings.cfg"
    fi
    chmod -R u+w "$out"
  '';

  runtime = "proton";
  executable = "HoI2.exe";

  # HoI2 / Doomsday (the 2005-2006 Europa-Engine generation) writes savegames
  # as .eug files into "scenarios/save games" *inside the install directory*,
  # not under Documents or AppData (that convention starts with HoI3).
  # Install-dir writes persist through the per-game fuse-overlayfs upper, so no
  # drive_c/users/steamuser relocation is needed -- hence the explicit empty
  # list. Re-verify once played that nothing lands in Documents/Paradox
  # Interactive.
  saveLocations = [ ];

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
    description = "Hearts of Iron II: Doomsday (2005 Paradox, English retail, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hearts-of-iron-ii";
  };
}
