{
  lib,
  pkgs,
  fetchIpfs,
  self,
}:

let
  # Pokémon Ranger: Shadows of Almia (2008 Creatures Inc. / HAL Laboratory,
  # published by Nintendo). Nintendo DS card image, the USA release, and the
  # second entry in the Ranger series — Guardian Signs, already in the tree,
  # is the third. The two are structurally identical packages and differ only
  # in the ROM they pin and in where the bytes come from.
  #
  # No-Intro "Pokemon Ranger - Shadows of Almia (USA).nds" — an untrimmed
  # 64 MiB / 67108864-byte cart image. Verified against the cart header and
  # the No-Intro DAT before pinning: internal title "POKE RANGER2", game code
  # YP2E (trailing E = USA, i.e. the NTR-YP2E-USA serial), maker code 01
  # (Nintendo), CRC32 5F520677, MD5 F957F5784ABF9557BE086FDB6FDC74CC, SHA-1
  # CA9C27752547E4D31FE5560265D9B7E09F9F83EB. All four hashes plus the serial
  # and size are an exact match for the "Pokemon Ranger - Shadows of Almia
  # (USA)" entry in libretro-database's No-Intro `Nintendo - Nintendo DS.dat`,
  # so this is the verified USA dump and not a trimmed image, a Virtual
  # Console re-release (crc 2643663D, a different dump) or a hack. Region was
  # read out of the header game code, not out of the file name.
  #
  # Provenance of the bytes: archive.org item `DS-No-Intro-2024-Myrient`, a
  # Myrient mirror of the No-Intro DS set that serves one TorrentZip per game
  # (34560239-byte zip, SHA-1 0d9993f321a06ce9cfeb88e5eafb7b0b93859216,
  # matching the item's own published checksum). This is the same item the
  # Explorers of Time / Explorers of Darkness siblings pin, so the DS titles
  # added in this batch all trace back to one auditable source.
  #
  # The archive serves the ROM zipped, so the FOD pins the zip and the build
  # extracts the single member to a raw .nds named after the slug — same shape
  # as the Explorers siblings and the Blue Rescue Team package.
  romArchive = fetchIpfs {
    cid = "QmZszGmHUj3cbhuuebmqTAcPTQBvWzAjc5ujfZVZiHWEoL";
    fallbackUrl = "https://archive.org/download/DS-No-Intro-2024-Myrient/Pokemon%20Ranger%20-%20Shadows%20of%20Almia%20%28USA%29.zip";
    hash = "sha256-gmBNvPq3qY18Xn4+VcJs1mpwcZ5c2hoLeHf+1I3z4rc=";
    name = "pokemon-ranger-shadows-of-almia--1.zip";
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
  name = "pokemon-ranger-shadows-of-almia--1";
  src = romArchive;
  runtime = "retroarch";
  executable = "pokemon-ranger-shadows-of-almia--1.nds";

  nativeBuildInputs = [ pkgs.unzip ];
  buildScript = ''
    mkdir -p $out
    unzip -p "$src" 'Pokemon Ranger - Shadows of Almia (USA).nds' \
      > $out/pokemon-ranger-shadows-of-almia--1.nds
  '';

  retroarch = {
    # NDS → melonDS libretro core (single .so under lib/retroarch/cores/, so
    # retroarch.nix auto-picks it from `cores`). `melonds` is the
    # execstack-cleared override defined above, as in every other DS title
    # here.
    cores = [ melonds ];

    # STYLUS-DRIVEN TITLE, same as Guardian Signs: the Capture Styler is
    # played by drawing loops around a wild Pokémon on the touch screen under
    # time pressure, and the attract screen is itself a touch gate. So the
    # touch mode has to follow the input device actually attached, exactly as
    # the Guardian Signs sibling does and for the same reason — melonDS's two
    # modes are mutually exclusive:
    #   no pad -> "Mouse": the pointer drives the stylus (what a desktop user
    #             has; verified below, a mouse click cleared the attract gate)
    #   pad    -> "Joystick": right stick moves the stylus as a velocity-based
    #             cursor, R3 taps, and the core draws a visible cursor, which
    #             is the only way to play this on a pad-only couch setup.
    # lib/retroarch.nix merges coreOptionsWithPad over coreOptions when
    # sdl2-jstest finds a gamepad at launch.
    #
    # Layout is the batch-wide DS default: both screens stacked and touching,
    # so the always-on bottom-screen Styler area stays full width.
    coreOptions = {
      melonds_screen_layout = "Top/Bottom";
      melonds_screen_gap = "0";
      melonds_touch_mode = "Mouse";
      melonds_threaded_renderer = "enabled";
    };

    coreOptionsWithPad = {
      melonds_touch_mode = "Joystick";
    };

    # Keyboard layout for solo play, identical to the other DS titles. Almia
    # uses the hardware buttons for menus, dialogue and the Ranger Browser;
    # all capture gameplay is the stylus.
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
    description = "Pokémon Ranger: Shadows of Almia (2008 Creatures Inc., Nintendo DS, via RetroArch / melonDS)";
    mainProgram = "pokemon-ranger-shadows-of-almia--1";
    platforms = [ "x86_64-linux" ];
  };
}
