{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # GOG offline installer (v2.0.0.4) wrapped in a RAR alongside the
  # Goodies (manual PDFs, expansion manual, wallpaper). Top level:
  #   setup_swat4_gold_2.0.0.4.exe   -- InnoSetup unicode 5.5.0
  #   Goodies/swat_4_manual.zip      -- PDFs and wallpapers, unused
  # The installer is the standard GOG "1409964317" SWAT 4 Gold Edition
  # build (base game + Stetchkov Syndicate expansion). innoextract
  # writes the playable tree into app/, with app/Content/ (base game)
  # and app/ContentExpansion/ (expansion) holding the Unreal Engine
  # 2.5 System/, Animations/, Maps/, ... subtrees.
  src = fetchIpfs {
    cid = "QmPt5rAY7fZXtgHvjWAaywnEYHgmba97qy9t38hCru29KT";
    fallbackUrl = "https://archive.org/download/swat-4-gold-edition_202604/SWAT%204%20-%20Gold%20Edition.rar";
    hash = "sha256-+JpYtbg5w9GmlEuOiHiznK6ZzgW/8HwMiBn9wbiFjoU=";
    name = "swat-4-gold-edition.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "swat-4";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  # Two-stage extract: unar the RAR (multi-top-level: setup .exe +
  # Goodies/), then innoextract --gog the SWAT 4 Gold installer. The
  # installer lays everything out under app/; we hoist that subtree
  # to $out so $out/Content/System/Swat4.exe and
  # $out/ContentExpansion/System/Swat4X.exe are addressable as
  # relative paths from the overlay root. Discard the Goodies, the
  # GOG hashdb/info/ico, and the bundled SDK zip (none are runtime).
  buildScript = ''
    mkdir -p "$TMPDIR/rar"
    unar -D -o "$TMPDIR/rar" "$src"
    mkdir -p "$TMPDIR/iss"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/rar/setup_swat4_gold_2.0.0.4.exe"
    mkdir -p "$out"
    cp -r "$TMPDIR/iss/app/." "$out"/
    chmod -R u+w "$out"
    rm -f "$out/goggame-1409964317.hashdb" \
          "$out/goggame-1409964317.ico" \
          "$out/goggame-1409964317.info" \
          "$out/SWAT4_SDK.zip"
  '';

  runtime = "proton";
  # Gold Edition entry point: the Stetchkov Syndicate expansion binary
  # under ContentExpansion/System/. It loads the base-game Content/
  # tree at runtime via the engine's package search paths, so launching
  # Swat4X.exe covers both the base campaign and the expansion. The
  # base-game-only entry would be Content/System/Swat4.exe.
  executable = "ContentExpansion/System/Swat4X.exe";

  # -nointro skips the Sierra/Irrational/Vivendi pre-menu Bink videos.
  # Those videos play their bundled audio through Wine's DirectSound
  # path; the bundled Creative-era DefOpenAL32.dll then fails to
  # (re)acquire the device for the in-game ALAudio subsystem, so menus
  # and gameplay come up silent while the intro had sound. Skipping the
  # intro keeps the device free for OpenAL. Documented fix on the GOG
  # forum and PCGamingWiki for both vanilla and Stetchkov Syndicate.
  executableArgs = [ "-nointro" ];

  # Unreal Engine 2.5 bootstraps from `Startup<GameName>.ini` (here
  # `StartupSwat4X.ini`) / `Startup.ini` in the *current working
  # directory* — not relative to the binary. mk-game's inner script
  # cds to $GAMEDIR (the overlay root), which is one level above
  # ContentExpansion/System/ where the Startup.ini lives, so the
  # engine bails out with "missing ini". Cd into the System dir before
  # exec so the engine finds its config tree.
  preRun = ''
    cd "$GAMEDIR/ContentExpansion/System"
  '';

  # saveLocations intentionally empty at stage time. SWAT 4 writes
  # profile data under Documents/SWAT 4 (engine's default) but the
  # exact subdirs only get created on first run; an interactive test
  # pass will confirm the layout before this list is populated.

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
    description = "SWAT 4: Gold Edition (Irrational Games 2005, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "swat-4";
  };
}
