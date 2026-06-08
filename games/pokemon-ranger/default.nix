{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Ranger (2006 HAL/Nintendo). Nintendo DS card.
  #
  # PLACEHOLDER ROM — NOT FINAL.
  # The seeded source below is the European "(E)(FireX)" dump (internal
  # game code ARGP, 32 MiB trimmed) — the only Pokémon Ranger image that
  # was directly fetchable from a live mirror at staging time (myrient
  # shut down 2026-03-31; the archive.org No-Intro DS per-game sets are
  # truncated to the early alphabet and carry no "P" titles). It exists
  # purely to validate the RetroArch + melonDS wiring end-to-end.
  #
  # Before this game leaves stage/: replace with the No-Intro
  # "Pokemon Ranger (USA).nds" (game code ARZE, 67108864 bytes), refresh
  # `hash`, set `fallbackUrl` to its source, then pin and swap `cid`.
  rom = fetchIpfs {
    cid = "QmZHUyEk66jfC4EA9oxPwQqqU2HH5kbyqvDeGEjtsd6h5f";
    fallbackUrl = "";
    hash = "sha256-qK0dDWh5b+v86h8s8BI6HjVVMqW14rNsPDnxxoU6d+E=";
    name = "pokemon-ranger.nds";
  };

  # The nixpkgs melonDS core ships its ARM-JIT dispatcher assembled from
  # a hand-written object that lacks a `.note.GNU-stack` section, so the
  # linker stamps the whole .so with an executable stack (PT_GNU_STACK
  # flags RWE). RetroArch dlopen()s the core, glibc then tries to remap
  # the main thread stack PROT_EXEC, and on a hardened kernel that mmap
  # is refused:
  #   melonds_libretro.so: cannot enable executable stack as shared
  #   object requires: Invalid argument
  # The core never loads, RetroArch falls back to its menu, and the game
  # "does nothing". The exec-stack request is spurious — the JIT runs
  # from mmap(PROT_EXEC) heap pages, never the stack — so clearing the
  # flag with `execstack -c` is safe and lets the core load.
  melonds = pkgs.libretro.melonds.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.prelink ];
    postFixup = (old.postFixup or "") + ''
      execstack -c "$out"/lib/retroarch/cores/melonds_libretro.so
    '';
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-ranger";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-ranger.nds";

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. DeSmuME
    # (`libretro.desmume`) is the alternative if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play. Pokémon Ranger is a stylus-driven
    # game; melonDS maps the touch screen to the mouse, so the on-screen
    # circling is done with the pointer. These binds cover the few
    # hardware-button prompts (confirm / cancel / menu).
    #   arrows     D-pad
    #   z          B
    #   x          A
    #   a          Y
    #   s          X
    #   q / e      L / R
    #   enter      Start
    #   rshift     Select
    settings = {
      input_player1_up = "up";
      input_player1_down = "down";
      input_player1_left = "left";
      input_player1_right = "right";
      input_player1_b = "z";
      input_player1_a = "x";
      input_player1_y = "a";
      input_player1_x = "s";
      input_player1_l = "q";
      input_player1_r = "e";
      input_player1_start = "enter";
      input_player1_select = "rshift";
    };
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Pokémon Ranger (via RetroArch / melonDS)";
    mainProgram = "pokemon-ranger";
    platforms = [ "x86_64-linux" ];
  };
}
