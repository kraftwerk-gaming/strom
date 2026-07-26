{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon HeartGold Version (2009 Game Freak / Nintendo). Nintendo DS card,
  # the enhanced remake of Gold/Silver. USA release: 128 MiB untrimmed .nds,
  # internal title "POKEMON HG", game code IPKE. Region confirmed from the ROM
  # header (game code, not the archive filename) — see the fallbackUrl item.
  rom = fetchIpfs {
    cid = "QmRheuPttVwksywqHqjMigShz9P6R7oswRgZLSZ5ahj2xU";
    fallbackUrl = "https://archive.org/download/pokemon-heart-gold-version/Pokemon%20HeartGold%20Version.nds";
    hash = "sha256-J2fiy4CswgYHQjLBCjt0pHnkWkcvLvn4S7/FXjatli0=";
    name = "pokemon-heartgold.nds";
  };

  # The nixpkgs melonDS core ships its ARM-JIT dispatcher assembled from a
  # hand-written object that lacks a `.note.GNU-stack` section, so the linker
  # stamps the whole .so with an executable stack (PT_GNU_STACK flags RWE).
  # RetroArch dlopen()s the core, glibc then tries to remap the main thread
  # stack PROT_EXEC, and on a hardened kernel that mmap is refused:
  #   melonds_libretro.so: cannot enable executable stack as shared
  #   object requires: Invalid argument
  # The core never loads, RetroArch falls back to its menu, and the game
  # "does nothing". The exec-stack request is spurious — the JIT runs from
  # mmap(PROT_EXEC) heap pages, never the stack — so clearing the flag with
  # `execstack -c` is safe and lets the core load.
  melonds = pkgs.libretro.melonds.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.prelink ];
    postFixup = (old.postFixup or "") + ''
      execstack -c "$out"/lib/retroarch/cores/melonds_libretro.so
    '';
  });
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemon-heartgold";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-heartgold.nds";

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/, so
    # retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. DeSmuME (`libretro.desmume`)
    # is the alternative if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play. HeartGold is largely D-pad + A/B driven;
    # melonDS maps the touch screen to the mouse for the few stylus prompts.
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
    description = "Pokémon HeartGold Version (2009 Game Freak, Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-heartgold";
    platforms = [ "x86_64-linux" ];
  };
}
