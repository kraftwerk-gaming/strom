{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Mario Party (USA, 1998 Hudson Soft / Nintendo). The original
  # 4-player board-game party title for the Nintendo 64. Sourced as a
  # 32 MiB ROM inside a per-game .zip from an archive.org N64 romset.
  # The archived ROM is in the byte-swapped v64 layout (magic
  # 0x37804012); the build converts it to the native big-endian z64
  # format (magic 0x80371240) with `dd conv=swab` so the executable is
  # a genuine .z64. mupen64plus-next handles the game without extra
  # config.
  romArchive = fetchIpfs {
    cid = "QmR3xWX7DFfmYGaNpXs5yELAcFd48RWtauRDhCtRykU8GW";
    fallbackUrl = "https://archive.org/download/nintendo-64-06-23-1996-completed-409-games-100-rename_20220729/Nintendo%2064%20-%2006-23-1996%20-%20Completed%20-%20409%20Games%20-%20100%25%20Rename%2FM%20-%20100%25%20-%20Completed%20-%20100%25%20Rename%2FMario%20Party%20%28USA%29.zip";
    hash = "sha256-5KRoIrzGu8aoGF+LSPp8pp1KNaCUIARAlYdnyK1QHBE=";
    name = "mario-party.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mario-party";
  src = romArchive;
  runtime = "retroarch";
  executable = "mario-party.z64";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    # The zip ships the ROM in byte-swapped v64 order; swab it to native
    # big-endian z64 (0x37804012 -> 0x80371240).
    unzip -p "$src" 'Mario Party (USA).n64' | dd conv=swab > $out/mario-party.z64
  '';

  retroarch = {
    cores = [ pkgs.libretro.mupen64plus ];

    # Keyboard layout for solo play (matches the other N64 games here).
    #   arrows     analog stick (movement)
    #   wasd       C-buttons (camera)
    #   ijkl       D-pad
    #   z          N64 A
    #   x          N64 B
    #   f          Z trigger
    #   q / e      L / R shoulder
    #   enter      Start
    #   rshift     Select
    #
    # mupen64plus-next with the default `alt-map = False` maps libretro
    # B -> N64 A and libretro Y -> N64 B; libretro A and X are unused,
    # so they are nulled to keep RetroArch's hardcoded keyboard defaults
    # from shadowing our binds.
    settings = {
      input_player1_a = "nul";
      input_player1_b = "z";
      input_player1_x = "nul";
      input_player1_y = "x";
      input_player1_start = "enter";
      input_player1_select = "rshift";
      input_player1_l = "q";
      input_player1_r = "e";
      input_player1_l2 = "f"; # N64 Z trigger
      # f is RetroArch's default fullscreen toggle; clear it so the Z
      # trigger bind wins.
      input_toggle_fullscreen = "nul";
      input_player1_up = "i";
      input_player1_down = "k";
      input_player1_left = "j";
      input_player1_right = "l";
      # Left analog stick (movement).
      input_player1_l_x_plus = "right";
      input_player1_l_x_minus = "left";
      input_player1_l_y_plus = "down";
      input_player1_l_y_minus = "up";
      # Right analog stick = N64 C-buttons (camera).
      input_player1_r_x_plus = "d";
      input_player1_r_x_minus = "a";
      input_player1_r_y_plus = "s";
      input_player1_r_y_minus = "w";
    };
  };

  meta = {
    description = "Mario Party (via RetroArch / mupen64plus-next)";
    mainProgram = "mario-party";
    platforms = [ "x86_64-linux" ];
  };
}
