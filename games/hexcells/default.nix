{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
}:

let
  src = fetchIpfs {
    cid = "QmV1iDcdhaciYGHf6FLcZ3FNaYneqPn9DTZTcuw2bcKHsu";
    fallbackUrl = "https://archive.org/download/fkeoflg/IGG-Hexcells.v1.02.rar";
    hash = "sha256-Ttzf7RlBz55U3w08TgbbAvyq8ikFqkTQkiMuj2bBHBI=";
    name = "hexcells.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "hexcells";

  inherit src;

  nativeBuildInputs = [ unar ];

  # IGG-encrypted RAR (password "igg-games.com"). Layout:
  # IGG-Hexcells.v1.02/{Hexcells.exe, Hexcells_Data/, IGG-GAMES.COM.url, README.txt}
  # Plain Unity Mono game (PE32 i386, Sept 2013 build, Unity 4.x), no DRM.
  # Drop the IGG advert URL shortcut and README.
  buildScript = ''
    mkdir -p "$out"
    unar -p "igg-games.com" -o "$TMPDIR/extract" "$src"
    cp -r "$TMPDIR/extract"/IGG-Hexcells.v1.02/* "$out"/
    rm -f "$out/IGG-GAMES.COM.url" "$out/README.txt"
  '';

  runtime = "proton";
  executable = "Hexcells.exe";

  # Unity 4.x's startup configuration dialog (resolution/quality picker)
  # misbehaves under gamescope's nested Xwayland: the cursor is visible
  # but click events don't land on the dialog buttons, and Enter maps to
  # the default-focused "Quit" button. Pass Unity's standalone player
  # arguments to skip the dialog and go straight into the game at the
  # gamescope output resolution.
  executableArgs = [
    "-screen-fullscreen"
    "1"
    "-screen-width"
    "1920"
    "-screen-height"
    "1080"
  ];

  extraBwrapArgs = [
    # Same workaround as loop-hero: input runtimes (here Unity's Mono
    # player) enumerate every /dev/input/event* node as a joystick. On
    # a laptop the touchpad's absolute X/Y axes get treated as analog
    # stick input and pull the cursor off the menu buttons, so clicks
    # never land. Mask /dev/input from the sandbox; mouse + keyboard
    # still arrive via Xwayland.
    "--tmpfs /dev/input"
  ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Unity 4.x's player uses raw X11 pointer input. Force-grab keeps
      # cursor + button events locked to the game window so menu clicks
      # actually land on the buttons under nested Xwayland.
      "--force-grab-cursor" = true;
    };
  };

  env = {
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
  };

  meta = {
    description = "Hexcells (Matthew Brown 2014, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "hexcells";
  };
}
