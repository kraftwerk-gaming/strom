{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
}:

let
  # GTA Vice City PC v1.0 (2002 Rockstar). The archive zip contains the
  # original v1.0 installation files plus two well-known fan patches:
  # the SilentPatch / mouse-fix dinput8.dll wrapper at the root, and
  # the ThirteenAG widescreen fix in a sibling directory. Without those
  # the game is unplayable on modern hardware (mouselook bug + cropped
  # 4:3 UI on widescreen displays).
  src = fetchIpfs {
    cid = "Qmb8B8Haj6BtUH8VNEmsSUCiSa9KTvg1gAZpCK5RVhhYXo";
    fallbackUrl = "https://archive.org/download/grand-theft-auto-vice-city-1.0/Grand%20Theft%20Auto%20Vice%20City%201.0.zip";
    hash = "sha256-9ICUp48nQJgOB2CpA2BzjhPa+aSQJsGAjNrASdfAS5Y=";
    name = "grand-theft-auto-vice-city.zip";
  };

  # GInput (Silent/CookiePLMonster) VC build 1.11a: VC's native pad support
  # is DirectInput-only with a broken fixed mapping (same story as San
  # Andreas -- modern XInput pads get D-pad-only movement, the stick
  # duplicates the D-pad, and buttons like enter-vehicle go unmapped).
  # GInput rewrites controls onto XInput so the pad maps like the console
  # versions. Loaded as an ASI by the ThirteenAG d3d8 shim already present
  # (the loader that pulls the Widescreen Fix .asi in). Blog-hosted (no
  # GitHub release / tag); pinned by hash (1.11a is the last VC release).
  ginput = fetchurl {
    url = "https://silent.rockstarvision.com/uploads/GInputVC.zip";
    hash = "sha256-ttM9sZwCT6At5Z9IGXu1S+fXMHAQQJCk2eSWBqRRtdM=";
    name = "GInputVC-1.11a.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "grand-theft-auto-vice-city";

  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/outer"
    # The outer zip nests another zip with the actual v1.0 game data
    # (audio/, anim/, models/, plus stock gta-vc.exe). Extract that as
    # the base, then overwrite with the outer's patched gta-vc.exe and
    # dinput8.dll mouse-fix wrapper, and merge the ThirteenAG widescreen
    # fix per its readme. Use -o so the patched files overwrite the
    # stock ones from the inner zip.
    unzip -q -o "$TMPDIR/outer/Grand Theft Auto Vice City.zip" -d "$TMPDIR/game"
    cp -f "$TMPDIR/outer/gta-vc.exe" "$TMPDIR/outer/dinput8.dll" "$TMPDIR/game"/
    cp -rf "$TMPDIR/outer/Widescreen Fix/GTAVC.WidescreenFix"/. "$TMPDIR/game"/
    cp -rf "$TMPDIR/outer/Widescreen Fix/GTAVC.WidescreenFrontend"/. "$TMPDIR/game"/
    cp -r "$TMPDIR/game"/. "$out"/

    # GInput: swap VC's broken native DirectInput pad handling for XInput
    # (correct console-style mapping incl. enter-vehicle, separate stick vs
    # D-pad). The ThirteenAG d3d8 ASI loader here scans scripts/ (where the
    # Widescreen Fix .asi lives), NOT the game root, so GInputVC.asi + its
    # ini go in scripts/; the button-prompt .txd models merge into models/.
    unzip -q -o ${ginput} GInputVC.asi GInputVC.ini -d "$out/scripts"
    unzip -q -o ${ginput} 'models/*' -d "$out"
  '';

  runtime = "proton";
  executable = "gta-vc.exe";

  saveLocations = [ "Documents/GTA Vice City User Files" ];

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

  env = {
    # Load both fan patches: dinput8 is the SilentPatch / mouse-fix
    # shim, d3d8 is the widescreen patch's d3d8-to-d3d9 translator.
    WINEDLLOVERRIDES = "d3d8,dinput8=n,b";
  };

  meta = {
    description = "Grand Theft Auto: Vice City (2002 Rockstar, PC v1.0 + SilentPatch + ThirteenAG Widescreen Fix, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "grand-theft-auto-vice-city";
  };
}
