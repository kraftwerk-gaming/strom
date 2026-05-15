{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  # GOG Windows release of TowerFall Ascension 2.5.0.6, packaged as a
  # zip wrapper around the InnoSetup installer (base game) plus the
  # Dark World DLC InnoSetup installer and a couple of bonus zips
  # (wallpapers/avatars). TowerFall is XNA / .NET Framework 4.0 with
  # SharpDX.DirectInput for gamepads, so it runs under Proton's bundled
  # dotnet stack without extra winetricks verbs. Layout inside the
  # outer zip:
  #   towerfall_ascension/setup_towerfall_ascension_2.5.0.6.exe
  #   towerfall_ascension/setup_towerfall_ascension_dark_world_2.4.0.5.exe
  #   towerfall_ascension/towerfall_ascension_avatars.zip
  #   towerfall_ascension/towerfall_ascension_wallpaper.zip
  #   towerfall_ascension/towerfall_dw_wallpaper.zip
  # Both InnoSetup installers drop their payload at app/* (with the DLC
  # adding a sibling DarkWorldContent/ tree); we innoextract both and
  # merge the app/ trees into $out.
  #
  # fallbackUrl intentionally empty: this exact zip bundle was supplied
  # directly by the operator; there is no public archive.org mirror
  # with matching SHA-256 bytes. The IPFS path is the only retrieval
  # route until a non-IPFS mirror is identified.
  installer = fetchIpfs {
    cid = "QmX1jKGFedEKzuHxh1WdSEYzLQF9JP1eVCGD2RqwJWSigo";
    fallbackUrl = "";
    hash = "sha256-ECVFsep2EMMGT3MbaVkTu7H9wWoZ1UhKqevLP+G7g0I=";
    name = "towerfallascension.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "towerfall-ascension";

  ipfsSources = [ installer ];
  src = installer;

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    # Unpack the outer GOG-Unlocked wrapper zip; it contains the two
    # InnoSetup .exe installers plus a few bonus zips we don't ship.
    unzip -q "$src" -d "$TMPDIR/outer"
    cd "$TMPDIR/outer/towerfall_ascension"
    # Base game: drops the payload at app/TowerFall.exe + app/Content/.
    innoextract --gog -d "$TMPDIR/base" setup_towerfall_ascension_2.5.0.6.exe
    # Dark World DLC: drops app/DarkWorldContent/ + a goggame-*.info
    # alongside the base app/ tree. The two trees merge cleanly because
    # the DLC only adds new files; it does not overwrite base content.
    innoextract --gog -d "$TMPDIR/dlc" setup_towerfall_ascension_dark_world_2.4.0.5.exe
    cp -r "$TMPDIR/base/app"/. "$out"/
    cp -r "$TMPDIR/dlc/app"/. "$out"/
    # The __support/save/ tree shipped by the GOG installer is NOT
    # discardable cruft: it is the seed config TowerFall.exe expects to
    # find next to the binary on first launch. In particular,
    # Gamepad_Config/Default.xml registers <id>default</id>, the key
    # TowerFall.NewGamepadInput's ctor unconditionally reads from its
    # internal dictionary while constructing input for every pad slot.
    # Without these files the game throws
    # KeyNotFoundException: 'default' at TFGame.Load and never reaches
    # the main menu. Promote Gamepad_Config/ and the *_Config.xml
    # siblings to the install root (where the game's pad-config guide
    # documents them living, alongside TowerFall.exe).
    if [ -d "$TMPDIR/base/app/__support/save/Gamepad_Config" ]; then
      cp -r "$TMPDIR/base/app/__support/save/Gamepad_Config" "$out/"
    fi
    for __seed in "$TMPDIR/base/app/__support/save/"*.xml; do
      [ -e "$__seed" ] || continue
      cp "$__seed" "$out/"
    done
    # Drop the remaining GOG installer cruft: webcache, the (now-empty)
    # support tree, and Workshop/Examples bookkeeping.
    rm -rf "$out/__support" "$out/__redist" "$out/webcache.zip" \
           "$out/Workshop" 2>/dev/null || true
  '';

  runtime = "proton";
  executable = "TowerFall.exe";

  # XNA / SharpDX TowerFall writes its savefile and config to
  # %USERPROFILE%\Documents\My Games\TowerFall on Windows; under Proton
  # that is drive_c/users/steamuser/Documents/My Games/TowerFall. Mirror
  # it into ~/.strom/towerfall-ascension so a compatdata wipe does not
  # nuke unlocks and gamepad bindings. Verify exact path on first launch.
  saveLocations = [ "Documents/My Games/TowerFall" ];

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
    description = "TowerFall Ascension + Dark World (Matt Makes Games, GOG v2.5.0.6, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "towerfall-ascension";
  };
}
