{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

# Jagged Alliance 2 (Sir-Tech 1999), turn-based tactics.
#
# Runs natively via ja2-stracciatella, the open-source engine
# reimplementation, which reads the original GOG game DATA directly (it has
# its own case-insensitive VFS, so the mixed-case GOG `Data/*.slf` tree works
# unmodified). This sidesteps the DirectDraw / Smacker-intro fragility of the
# 1999 Windows build under Proton (the GOG ja2.exe plays the intro but then
# crashes when starting a New Game -- a well-known DirectDraw / intro-video
# compatibility failure on modern stacks).
#
# nixpkgs `ja2-stracciatella` is `meta.broken = true` and does not build; the
# contained, no-global-changes fix lives in ./ja2-stracciatella.nix (miniaudio
# header, CMake 4 policy, sol2 3.2.2). See that file for the details.
let
  ja2-stracciatella = pkgs.callPackage ./ja2-stracciatella.nix { };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "jagged-alliance-2";

  # GOG JA2 v1.12 -- a plain GOG Inno installer; innoextract yields the game
  # tree with ja2.exe + Data/ at the root. We keep the whole tree (the engine
  # reads the .slf data files from Data/); the ja2.exe / Windows DLLs are just
  # ignored by the native engine.
  src = fetchIpfs {
    cid = "QmQvbULQxcCeL36v2eJENNF7MrhAmYEaXNeof9xRSfkTt2";
    fallbackUrl = "magnet:?xt=urn:btih:EB95F545991191F90C1FBE731C332F23FC6F59EF&dn=Jagged%20Alliance%202%20%5BL%5D%20%5BENG%20%2F%20ENG%5D%20%281999%29%20%5BGOG%5D";
    hash = "sha256-/09MOlTz6q5HL4yxxZzOqfcLbUB/di/rUJfDVKYqYF4=";
    name = "setup_jagged_alliance_2_1.12.exe";
  };

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out"
    innoextract -d "$out" $src
    # GOG Inno layout: game tree under app/; flatten it and drop the
    # installer-only scratch dirs.
    if [ -d "$out/app" ]; then
      mv "$out/app"/* "$out"/
      rmdir "$out/app"
    fi
    # Merge support data (Data/Temp/, …) from __support into the game root.
    if [ -d "$out/__support/app" ]; then
      cp -rn "$out/__support/app/." "$out/"
    fi
    if [ -d "$out/__support/add" ]; then
      cp -rn "$out/__support/add/." "$out/"
    fi
    rm -rf "$out/__support" "$out/tmp" "$out/commonappdata"
  '';

  runtime = "native";

  # stracciatella resolves the original game data from -gamedir via its own
  # case-insensitive VFS, reading it READ-ONLY. We point -gamedir at the
  # immutable build output ($STROM_GAMEDATA) rather than the fuse-overlayfs
  # merged $GAMEDIR: the overlay can intermittently fail to present the
  # lowerdir's `Data/` at launch (mount-ready vs. first-read race), and when
  # the engine's `read_dir()` of the gamedir misses `Data`, its caseless
  # resolver falls back to the literal lowercase `data` -> the VFS
  # "No such file or directory" init failure. The store path always has
  # `Data/` and never races. resversion ENGLISH = the GOG English 1.12
  # release. Config + saves land under ~/.ja2/ (= $HOME = $STROM_GAMEDIR), so
  # they persist across overlay/prefix resets.
  runScript = ''
    exec ${ja2-stracciatella}/bin/ja2 -gamedir "$STROM_GAMEDATA" -resversion ENGLISH
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Jagged Alliance 2 (Sir-Tech 1999, via ja2-stracciatella)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "jagged-alliance-2";
  };
}
