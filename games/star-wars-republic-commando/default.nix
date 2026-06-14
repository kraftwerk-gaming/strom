{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # Star Wars: Republic Commando (LucasArts 2005), GOG re-release v2.0.0.6,
  # repacked as a single RAR. The RAR holds a top-level wrapper directory
  # `Star Wars - Republic Commando 2.0.0.6 [GOG]/` with one GOG Inno Setup
  # installer (setup_sw_republic_commando_2.0.0.6.exe) plus the manual zip:
  # unar yields the installer, innoextract --gog yields the game tree under
  # GameData/ (the Unreal Engine 2 game data + System/SWRepublicCommando.exe),
  # with GOG installer debris under app/ tmp/ __redist/ commonappdata/.
  src = fetchIpfs {
    cid = "QmZe2GTKZQG97ibJk9mSKmqEXNtFKedEDzjZy31aHBra7U";
    fallbackUrl = "https://archive.org/download/star-wars-republic-commando-2.0.0.6-gog/Star%20Wars%20-%20Republic%20Commando%202.0.0.6%20%5BGOG%5D.rar";
    hash = "sha256-nIbgcFgFYbDPmLdgv2cV9LOsSq11uo52CSsI1nnMgao=";
    name = "star-wars-republic-commando-2.0.0.6-gog.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "star-wars-republic-commando";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  # Unpack the RAR, innoextract --gog the installer, then promote the
  # extracted game tree to $out root. This GOG installer lays the entire
  # game under `app/` (app/GameData/ + app/LaunchRC.exe + GOG debris), so
  # we copy app/'s contents up to $out — the executable path is then
  # GameData/System/SWRepublicCommando.exe relative to the overlay.
  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" "$src"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/rar/Star Wars - Republic Commando 2.0.0.6 [GOG]/setup_sw_republic_commando_2.0.0.6.exe"
    cp -r "$TMPDIR/iss/app"/. "$out"/
    chmod -R u+w "$out"
    # GOG installer debris + GOG Galaxy support: not needed at runtime. The
    # game lives under $out/GameData/ (System/, Movies/, Maps/, ...). The
    # GOG launcher LaunchRC.exe is bypassed — we exec the engine directly.
    rm -rf "$out/__support"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.script "$out/goggame-"*.ico \
          "$out/LaunchRC.exe" "$out/Manual.pdf" "$out/webcache.zip"
  '';

  runtime = "proton";

  # GameData/System/SWRepublicCommando.exe is the Unreal Engine 2 game
  # binary. -nointro skips the LucasArts/intro logo movies (the AVI
  # playback path is the usual Proton/Wine startup hang for this title), so
  # the engine boots straight to the main menu.
  executable = "GameData/System/SWRepublicCommando.exe";
  executableArgs = [ "-nointro" ];

  # The UE2 engine reads its packages/config relative to the System/ dir;
  # CD there so it resolves ..\ paths (Maps, Textures, Sounds) against
  # GameData/ rather than the overlay root.
  preRun = ''
    cd "$GAMEDIR/GameData/System"
  '';

  # Saves + the generated User.ini/SWRepublicCommando.ini persist via the
  # per-game fuse-overlayfs upper (the engine writes Save/ and *.ini next
  # to its binary under GameData/System/, not under drive_c/users/...).
  saveLocations = [ ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # SWRC ties menu mouse sensitivity to frame rate and toggles cursor
      # visibility between menu and gameplay; the grab keeps relative-mouse
      # mode stable so the camera/menu input stays usable.
      "--force-grab-cursor" = true;
    };
  };

  env = {
    STEAM_COMPAT_APP_ID = "6000";
    SteamAppId = "6000";
    # UE2 is 32-bit; large-address-aware helps on memory-heavy levels.
    WINE_LARGE_ADDRESS_AWARE = "1";
    # The engine ties physics/menu mouse speed to frame rate; clamp the
    # d3d swapchain to 60 so the menu cursor and in-game camera stay sane.
    DXVK_FRAME_RATE = "60";
  };

  meta = {
    description = "Star Wars: Republic Commando (LucasArts 2005, Unreal Engine 2, GOG v2.0.0.6, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "star-wars-republic-commando";
  };
}
