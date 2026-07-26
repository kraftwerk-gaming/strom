{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Pearl (2006 Game Freak / Nintendo). Nintendo DS card.
  #
  # Source: No-Intro "Pokemon - Pearl Version (USA) (Rev 5)" — the full,
  # untrimmed USA dump (game code APAE, maker 01, 67108864 bytes / 64 MiB),
  # served as a single TorrentZipped archive by the archive.org per-game
  # item `pokemon-pearl-version-usa-rev-5_202409`. Rev 5 is the USA image
  # No-Intro catalogues and the same revision used to stage the sibling
  # Pokémon Diamond. The ROM is pinned on IPFS; `fallbackUrl` is that
  # archive.org direct download, used only if the gateways are down.
  rom = fetchIpfs {
    cid = "QmVTDuEEt71Ltfhu6fZLvtWRQ7NPT3Gkys4pcVHg717E8E";
    fallbackUrl = "https://archive.org/download/pokemon-pearl-version-usa-rev-5_202409/Pokemon%20-%20Pearl%20Version%20%28USA%29%20%28Rev%205%29.zip";
    hash = "sha256-xfekEi27fTSoiQc+QFiYM8u1Zzr/NGZjBhJzN/K2s7g=";
    name = "pokemon-pearl.nds";
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
  name = "pokemon-pearl";
  src = rom;
  runtime = "retroarch";
  executable = "pokemon-pearl.nds";

  # The source is the TorrentZip archive; extract the single ROM it holds.
  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon - Pearl Version (USA) (Rev 5).nds' > $out/pokemon-pearl.nds
  '';

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/,
    # so retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above. DeSmuME
    # (`libretro.desmume`) is the alternative if a future title regresses.
    cores = [ melonds ];

    # Keyboard layout for solo play. Pokémon Pearl is a stylus-driven
    # game; melonDS maps the touch screen to the mouse, so on-screen taps
    # are done with the pointer. These binds cover the hardware buttons.
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
    description = "Pokémon Pearl (2006 Nintendo, Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-pearl";
    platforms = [ "x86_64-linux" ];
  };
}
