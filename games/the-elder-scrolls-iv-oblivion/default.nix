{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # The Elder Scrolls IV: Oblivion - Game of the Year Edition (Bethesda
  # 2006 base + Knights of the Nine 2006 + Shivering Isles 2007), GOG
  # offline installer v1.2.0416 build 12788. The archive.org item ships
  # a single .rar wrapping the standard GOG multi-part installer:
  #
  #   The Elder Scrolls IV Oblivion/
  #     setup_oblivion_1.2.0416_cs_(12788).exe        Inno Setup wrapper
  #     setup_oblivion_1.2.0416_cs_(12788)-1.bin      GOG-Galaxy slob 1
  #     setup_oblivion_1.2.0416_cs_(12788)-2.bin      GOG-Galaxy slob 2
  #
  # innoextract --gog reads the .exe and pulls both .bin payloads
  # alongside; the game tree (Oblivion.exe + Data/ with Oblivion.esm,
  # DLCShiveringIsles.esp, Knights.esp + matching BSAs) lands at app/
  # root in the extract.
  #
  # Engine is Gamebryo (the same family Morrowind uses, but with no
  # mature open-source reimplementation - OpenMW Oblivion support is
  # still pre-alpha as of 2026). So unlike morrowind/openmw, this
  # package drives the original Oblivion.exe under Proton.
  src = fetchIpfs {
    cid = "QmToRXKY2pRbvyBTUGX42LYzYbEbbRto7D2humBLBnRkT9";
    fallbackUrl = "https://archive.org/download/the-elder-scrolls-iv-oblivion-goty/The%20Elder%20Scrolls%20IV%20Oblivion%20GOTY.rar";
    hash = "sha256-GinFDK3onxLET10FYmnyUSsLu6CIJ3FFlINMNq/X5kI=";
    name = "the-elder-scrolls-iv-oblivion-goty.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-elder-scrolls-iv-oblivion";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  # Layer 1: rar -> directory containing the GOG installer triple
  # (setup_*.exe + setup_*-1.bin + setup_*-2.bin) inside a
  # "The Elder Scrolls IV Oblivion" subdir. Layer 2: innoextract --gog
  # walks the .exe, reassembles the .bin slobs and writes the game tree
  # to $TMPDIR/inno. The actual game payload lives at app/ (Oblivion.exe,
  # Data/, DLC stubs); the rest is GOG installer debris (commonappdata,
  # tmp, __redist, __support, goggame-metadata) that the Proton runtime
  # never touches.
  buildScript = ''
    mkdir -p "$out" "$TMPDIR/rar" "$TMPDIR/inno"
    unar -q -o "$TMPDIR/rar" "$src"
    setup_exe=$(find "$TMPDIR/rar" -iname 'setup_oblivion*.exe' | head -1)
    innoextract --gog -d "$TMPDIR/inno" "$setup_exe"
    cp -r "$TMPDIR/inno/app"/. "$out"/
    chmod -R u+w "$out"
    # GOG installer debris: never read by Oblivion.exe at runtime.
    rm -rf "$out/__redist" "$out/__support" "$out/commonappdata" "$out/tmp"
    rm -f "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.script "$out"/goggame-*.ico \
          "$out"/goggame-*.dll \
          "$out"/webcache.zip "$out"/autorun.exe "$out"/autorun.inf
  '';

  runtime = "proton";
  executable = "Oblivion.exe";

  saveLocations = [
    # Gamebryo writes Oblivion.ini, RendererInfo.txt and the Saves/
    # subtree under Documents/My Games/Oblivion. Relocate so a prefix
    # wipe leaves character saves and graphics tuning intact.
    "Documents/My Games/Oblivion"
  ];

  env = {
    # Steam appid for Oblivion GOTY Deluxe (22330). Protonfixes keys on
    # this and games that probe the Steam env find a coherent identity.
    STEAM_COMPAT_APP_ID = "22330";
    SteamAppId = "22330";
    # Oblivion.exe is a 32-bit Gamebryo binary; LAA lets the engine
    # address >2 GiB of virtual memory which helps with the high-res
    # texture mods most players layer on the GOTY data.
    WINE_LARGE_ADDRESS_AWARE = "1";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Oblivion's mouse look uses DirectInput relative mode; under a
      # nested Xwayland compositor without an explicit grab the camera
      # stutters because absolute positions keep arriving.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "The Elder Scrolls IV: Oblivion GOTY (Bethesda 2006 GOG v1.2.0416, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-elder-scrolls-iv-oblivion";
  };
}
