{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  lhasa,
  easyrpg-player,
}:

let
  src = fetchIpfs {
    cid = "QmPr1FAGbr5genqeZcMDzSrRfFpEjeDcR8pUU3VecYta4o";
    fallbackUrl = "https://archive.org/download/yume-nikki-010a/YumeNikki_EN%20%28Playism%202012%29.zip";
    hash = "sha256-S5Rpaw2lMPdwGdSaioiJSi4z2KWJl8/plVlhOdPkI3M=";
    name = "YumeNikki_EN.zip";
  };

  # Extracted RPG Maker 2003 runtime, materialised as its own store path so
  # the runScript can point EasyRPG at it directly (see runScript comment).
  gameData = pkgs.runCommandLocal "yume-nikki-data" { inherit src; } ''
    mkdir -p "$out"
    ${unzip}/bin/unzip -q "$src" -d "$TMPDIR/zip"
    cd "$out"
    ${lhasa}/bin/lha xq "$TMPDIR/zip/YumeNikki_EN/YumeNikki.lzh"
    # lhasa writes the archive's raw Shift-JIS asset filenames to disk
    # verbatim. The host filesystem and EasyRPG both work in UTF-8, so
    # re-encode the names to UTF-8 once at build time -- otherwise the
    # game-root has mojibake filenames and asset lookups are fragile.
    # See the script. RPG_RT.ldb/.ini/.lmt/.exe are pure ASCII and stay
    # exactly as named (the script only touches non-ASCII entries).
    ${pkgs.python3}/bin/python3 ${./sjis-to-utf8.py} "$out"
  '';
in

self.lib.mkGame { inherit lib pkgs; } {
  name = "yume-nikki";

  # Yume Nikki (Kikiyama 2004-2007, RPG Maker 2003). Playism's 2012
  # official English release: a .zip wrapping a Setup.exe + Setup.ini
  # + UNLHA32.DLL + YumeNikki.lzh data archive + README. We bypass the
  # Wise/UNLHA installer at build time -- the .lzh is plain LHA and
  # extracts with lhasa, yielding the RPG Maker 2003 runtime
  # (RPG_RT.exe + RPG_RT.ini/ldb/lmt + Backdrop/CharSet/Sound/Picture
  # asset folders).
  #
  # We do NOT run the bundled RPG_RT.exe under Proton: the engine loads
  # its first System2 graphic (マイシステムa.xyz) by opening the bare
  # graphic name relative to the game root, without prepending System\
  # or the extension. Under Wine that resolves to overlay\マイシステムa,
  # which does not exist, so RPG_RT dies at startup with a Japanese
  # "file ... cannot be opened" MessageBox -- even with the prefix's
  # ANSI codepage correctly set to 932. This is a known RPG_RT/Wine
  # path-resolution incompatibility, not a locale bug. EasyRPG Player
  # is the well-trodden, native reimplementation of the RPG Maker
  # 2000/2003 runtime; it reads the same data files directly and loads
  # this game cleanly, so we drive the assets through it instead.
  inherit src;

  nativeBuildInputs = [
    unzip
    lhasa
    pkgs.python3
  ];

  buildScript = ''
    cp -r ${gameData}/. "$out"
  '';

  runtime = "native";

  executable = "RPG_RT.exe";

  # RPG Maker 2003 renders a fixed 320x240 backbuffer; let gamescope
  # integer-scale it to 1080p rather than nearest-neighbour 4:3.
  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  # EasyRPG reads the database (RPG_RT.ldb) strings, which store asset
  # references and the game title in CP932 (Shift-JIS); --encoding 932
  # decodes them. Saves (Save01.lsd ..) go to --save-path = $STROM_GAMEDIR
  # and persist there.
  #
  # --project-path points at the immutable nix-store game data, NOT at
  # $GAMEDIR (the fuse-overlayfs mount). The strom bwrap binds mount that
  # overlay onto its mountpoint twice -- once via `--ro-bind / /` and again
  # via `--bind $STROM_CACHEDIR $STROM_CACHEDIR` (the overlay lives under
  # the cache dir) -- and two fuse-overlayfs instances stacked on one point
  # return an inconsistent readdir: a path lookup of RPG_RT.ldb still
  # succeeds, but enumerating the directory yields nothing. EasyRPG detects
  # a project by scanning the directory for RPG_RT.ldb, so against the
  # overlay it sees an empty dir and drops to its "No games found" browser.
  # The game data never changes at runtime, so reading it straight from the
  # store (singly mounted, clean readdir) is correct and side-steps this.
  runScript = ''
    exec ${easyrpg-player}/bin/easyrpg-player \
      --project-path ${gameData} \
      --save-path "$STROM_GAMEDIR" \
      --encoding 932
  '';

  meta = {
    description = "Yume Nikki (Kikiyama, RPG Maker 2003 freeware; Playism 2012 official English release, via EasyRPG Player)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "yume-nikki";
  };
}
