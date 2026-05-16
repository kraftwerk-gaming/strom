{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Steam 2012 PC port of Jet Set Radio (Smilebit/SEGA 2000, Blitworks PC
  # port). Steam DRM has been stripped from this dump: the shipped
  # steam_api.dll is a no-op stub, so the game can launch without a
  # running Steam client. Anything that does poke at steamclient.dll is
  # served by lib/proton.nix's steamclient-stub via the standard
  # $HOME/.steam/sdk{32,64}/ symlinks.
  #
  # Archive layout: "Jet Set Radio/" top-level dir holds jetsetradio.exe
  # (main 32-bit game binary), jsrsetup.exe (graphics/key config tool),
  # CUSTOM/ + DATA/ + LANG/ asset trees, language-specific .resources.dll
  # subdirs (de/, es/, fr/, ja/), Steamclient.dll + steam_api.dll +
  # steam_w.dll, plus an Uninstall/ tree we drop.
  src = fetchIpfs {
    cid = "QmVfcnecdG5cfr9RJhHPCzrEqjqYQ2j5ZKxH5ndL4eZ5NF";
    fallbackUrl = "https://archive.org/download/jet.-set.-radio.-hd/Jet.Set.Radio.HD.zip";
    hash = "sha256-zA57RtmUwvHYyPw4kN3noOmcVsiqtAx8CAHQvsax6+k=";
    name = "jet-set-radio-steam.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "jet-set-radio";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/extract"
    cp -r "$TMPDIR/extract/Jet Set Radio/." "$out"/
    # Drop the Windows uninstaller tree; useless under proton.
    rm -rf "$out/Uninstall"
  '';

  runtime = "proton";
  executable = "jetsetradio.exe";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Jet Set Radio (Smilebit/SEGA 2000, Blitworks 2012 PC port, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "jet-set-radio";
  };
}
