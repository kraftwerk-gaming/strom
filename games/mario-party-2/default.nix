{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Mario Party 2 (USA, 1999 Hudson Soft / Nintendo). 32 MiB Nintendo 64
  # ROM in the native big-endian z64 format (magic 0x80371240). The NMWE
  # cartridge header ("E" region byte) confirms the USA release. Sourced
  # zipped from an archive.org N64 USA romset; the archive holds a single
  # TorrentZipped "Mario Party 2 (USA).z64", extracted at build time.
  # mupen64plus-next runs the board-game + minigame engine without extra
  # config.
  romArchive = fetchIpfs {
    cid = "QmSjX76DT5xbAG7zAWV1vuvABKzJWVqNH1J5wfZsDEyUFa";
    fallbackUrl = "https://archive.org/download/nintendo-64-pt-br_202508/Mario%20Party%202%20%28USA%29.zip";
    hash = "sha256-LNlA8WjWFJa7Kdx6BnQ+IahCUHPQIa1yu6oUW8SJ+Vg=";
    name = "mario-party-2.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "mario-party-2";
  src = romArchive;
  runtime = "retroarch";
  executable = "mario-party-2.z64";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Mario Party 2 (USA).z64' > $out/mario-party-2.z64
  '';

  retroarch = {
    cores = [ pkgs.libretro.mupen64plus ];

    # Keyboard layout for solo play (matches the other N64 games in this
    # flake — see super-mario-64 for the libretro→N64 mapping rationale).
    #   arrows     analog stick (movement / menu navigation)
    #   wasd       C-buttons
    #   ijkl       D-pad
    #   z          N64 A
    #   x          N64 B
    #   f          Z trigger
    #   q / e      L / R shoulder
    #   enter      Start
    #   rshift     Select
    settings = {
      # mupen64plus-next default (alt-map = False): libretro B → N64 A,
      # libretro Y → N64 B; libretro A and X are unused, nulled so the
      # RetroArch keyboard defaults don't shadow our binds.
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
      # Left analog stick (movement / minigame control).
      input_player1_l_x_plus = "right";
      input_player1_l_x_minus = "left";
      input_player1_l_y_plus = "down";
      input_player1_l_y_minus = "up";
      # Right analog stick = N64 C-buttons.
      input_player1_r_x_plus = "d";
      input_player1_r_x_minus = "a";
      input_player1_r_y_plus = "s";
      input_player1_r_y_minus = "w";
    };
  };

  meta = {
    description = "Mario Party 2 (1999 Hudson Soft / Nintendo, N64, via RetroArch / mupen64plus-next)";
    mainProgram = "mario-party-2";
    platforms = [ "x86_64-linux" ];
  };
}
