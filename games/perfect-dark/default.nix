{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Perfect Dark (NTSC final, 2000 Rare/Nintendo). 32 MiB N64 ROM in
  # native big-endian z64 format (magic 0x80371240). One of the largest
  # N64 cartridges shipped (uses the Expansion Pak's 4 MB extra RAM for
  # high-detail mode). mupen64plus-next handles the Expansion Pak and
  # the game's microcode without extra config.
  rom = fetchIpfs {
    cid = "QmYdSV7dxZkWLxcVLbPctppR2YGPye1ryAArLk4QeBzWgx";
    fallbackUrl = "https://archive.org/download/pd.ntsc-final/pd.ntsc-final.z64";
    hash = "sha256-tBc+6Qum41FLF9fzQMbCSOKkxCn9w8Zx3YK79a/LsVI=";
    name = "perfect-dark.z64";
  };
in
(self.lib.retroarch.apply {
  inherit pkgs;
  cores = [ pkgs.libretro.mupen64plus ];
  preHook = ''
    mkdir -p ~/.strom/perfect-dark/saves \
             ~/.strom/perfect-dark/states
  '';
  settings.savefile_directory = "~/.strom/perfect-dark/saves";
  settings.savestate_directory = "~/.strom/perfect-dark/states";

  # Keyboard layout for solo play (matches the other N64 games in this
  # flake — see super-mario-64 for the libretro→N64 mapping rationale).
  #   arrows     analog stick (movement / aim)
  #   wasd       C-buttons (camera / aim)
  #   ijkl       D-pad (weapon function cycle)
  #   z          N64 A (fire)
  #   x          N64 B (crouch / cancel)
  #   f          Z trigger (alt-fire / aim mode)
  #   q / e      L / R shoulder
  #   enter      Start
  #   rshift     Select
  settings = {
    # mupen64plus-next default (alt-map = False): libretro B → N64 A,
    # libretro Y → N64 B; libretro A and X are unused.
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
    # Right analog stick = N64 C-buttons (look / aim).
    input_player1_r_x_plus = "d";
    input_player1_r_x_minus = "a";
    input_player1_r_y_plus = "s";
    input_player1_r_y_minus = "w";
  };
  args = [ (toString rom) ];
}).wrapper.overrideAttrs
  (_: {
    meta = {
      description = "Perfect Dark (via RetroArch / mupen64plus-next)";
      mainProgram = "retroarch";
      platforms = lib.platforms.linux;
    };
    passthru = {
      runtime = "retroarch";
      ipfsSources = [ rom ];
    };
  })
