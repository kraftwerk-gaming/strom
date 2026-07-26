{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokemon Stadium (2000 Nintendo, N64). USA cartridge dump in native
  # big-endian z64 format (magic 0x80371240). Uses the N64 Transfer Pak
  # in real hardware to import GB/GBC teams; the core plays the standalone
  # stadium/minigame modes without extra config. mupen64plus-next handles
  # the microcode out of the box.
  rom = fetchIpfs {
    cid = "QmZmBEfLXwXKU1k2rK4hCG1GkaUfnCwBpNoEpfM47vFntx";
    fallbackUrl = "https://archive.org/download/pokemon-stadium-2-usa_202402/Pokemon%20Stadium%20%28USA%29%20%28Rev%202%29.z64";
    hash = "sha256-otydFLrlA1vainygW5wW5hu1oZvl5wfdb24f6YzrpOo=";
    name = "pokemon-stadium.z64";
  };
  # ParaLLEl-RDP sizes its per-sync-index image arrays exactly once, in
  # RDP::init(), from the frontend's swapchain image count. RetroArch's
  # fast-forward clears the swap interval, which flips the Vulkan present mode
  # FIFO -> MAILBOX; on this WSI MAILBOX needs one more image (3 -> 4), so
  # get_sync_index() starts returning an index past the end of those vectors
  # and rdp.cpp:422 does an atomic refcount decrement through trailing heap
  # garbage -> SIGSEGV on the first toggle. The code that would resize them
  # (RDP::begin_frame) is dead -- its only wrapper has no call sites anywhere
  # in the repo or the shipped .so -- and the bounds assert is compiled out
  # under NDEBUG. Unfixed upstream (libretro/mupen64plus-libretro-nx#604), so
  # grow the arrays on demand when the frontend widens the index range.
  mupen64plus = pkgs.libretro.mupen64plus.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./parallel-rdp-ff-swapchain-oob.patch ];
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-stadium";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-stadium.z64";

  retroarch = {
    cores = [ mupen64plus ];

    # Pokemon Stadium 1/2 need a low-level RDP. Under the default GLideN64
    # Stadium 2 is black from boot and Stadium 1 turns white/corrupt after
    # the title card. ParaLLEl-RDP renders them correctly but segfaults in
    # RDP::complete_frame() the moment RetroArch fast-forwards (reproduced
    # against the VI interrupt path; SIGSEGV every time). Angrylion is the
    # reference software rasterizer: it renders both games correctly, is
    # unaffected by fast-forward, and measured 59.98 fps here at ~170% CPU
    # across its worker threads, so the accuracy costs nothing in practice.
    # rsp-plugin stays hle -- the core logs that it auto-falls back to
    # Parallel RSP when angrylion is selected.
    coreOptions = {
      "mupen64plus-rdp-plugin" = "parallel";
      "mupen64plus-rsp-plugin" = "hle";
      # Stadium 1/2 output 480i. ParaLLEl-RDP defaults to Bob
      # deinterlacing, which alternates fields every frame and makes the
      # picture visibly shake like a mistuned CRT. Weave keeps both fields
      # woven together for a stable image; the core only requires it be
      # paired with 1x upscaling, which is the default we use.
      "mupen64plus-parallel-rdp-deinterlace-method" = "Weave";
    };

    # Keyboard layout matches the other N64 games in this flake (see
    # perfect-dark / super-mario-64 for the libretro->N64 mapping).
    #   arrows     left analog stick
    #   wasd       C-buttons
    #   ijkl       D-pad
    #   z          N64 A
    #   x          N64 B
    #   f          Z trigger
    #   q / e      L / R shoulder
    #   enter      Start
    #   rshift     Select
    settings = {
      # mupen64plus-next default (alt-map = False): libretro B -> N64 A,
      # libretro Y -> N64 B; libretro A and X are unused.
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
      # Left analog stick.
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
    description = "Pokemon Stadium (2000 Nintendo, N64, via RetroArch / mupen64plus-next)";
    mainProgram = "pokemon-stadium";
    platforms = [ "x86_64-linux" ];
  };
}
