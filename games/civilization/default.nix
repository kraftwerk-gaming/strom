{
  self,
  lib,
  pkgs,
  fetchIpfs,
  dosbox-x,
  unar,
}:

let
  # Sid Meier's Civilization (MicroProse 1991, MS-DOS) - the original,
  # not Civ II / CivNet / the Windows remake. Asset is the archive.org
  # item `civ474.05`, an already-installed on-disk game directory of
  # build 474.05 (CIV.EXE dated 1992-10-12), the last patch of the
  # original DOS run, bundled with MicroProse's April 1994 sound-driver
  # update (SOUND.EXE + PSOUND.CVL/GSOUND.CVL/CONFIG.SND, see
  # README.SND in the tree). Chosen over the msdos_*/CIVILIZATION_201902
  # library zips, which carry a different, later-repacked CIV.EXE and
  # none of the 1994 drivers (no SOUND.EXE / CONFIG.SND / PSOUND.CVL /
  # GSOUND.CVL).
  #
  # The rar is RAR5, so p7zip cannot read it - `unar` (free, LGPL) does.
  # unar renames a single-rooted archive after the archive *file*, so the
  # game root lands under the store-path name rather than `civ474.05/`;
  # buildScript locates it by CIV.EXE and flattens it into $out. DOSBox
  # then mounts $out as C: with CIV.EXE at the root, exactly what
  # HDINST.BAT's `copy *.* %1\civ` produces on real hardware.
  #
  # CIV.EXE asks three questions before it starts - stock 1991 boot
  # sequence, not a packaging gap. Read off the actual frames, the
  # options are:
  #
  #   "Select graphics mode:"   1) VGA (256 color)  2) MCGA (256 color)
  #                             3) EGA (16 color)   4) Tandy 1000 (16 color)
  #   "Select sound mode:"      1) No sounds please 2) IBM sounds
  #                             3) Tandy sounds     4) AdLib/Sound Blaster
  #                             5) Roland MT-32 MIDI board
  #                             6) Custom sound driver
  #   (input device, untitled)  1. Mouse and Keyboard   2. Keyboard only
  #
  # runScript answers 1 / 6 / 1:
  #
  #   1 - VGA 256 colour, which is what [dosbox] machine=svga_s3 below
  #       emulates.
  #   6 - "Custom sound driver", i.e. the April 1994 MicroProse sound
  #       update (README.SND). Its CONFIG.SND ships pre-populated in the
  #       asset: bytes `50 00 20 00 20 02 ff ff` = driver letter 'P'
  #       (-> PSOUND.CVL, the OPL-3 FM path) at base 0x220, which is
  #       exactly the [sblaster] block below, so SOUND.EXE never has to
  #       be run. Options 1-5 are the stock 1991 drivers.
  #   1 - "Mouse and Keyboard". THIS is the mouse fix. Answer 2, or let
  #       the prompt default, and the game itself never touches INT 33h:
  #       no cursor is drawn, clicks are ignored, and no amount of
  #       DOSBox [sdl] autolock / gamescope --force-grab-cursor helps.
  #       Checked both ways headlessly on the main menu - with 1 the
  #       in-game arrow tracks the pointer and a click on "View Hall of
  #       Fame" opens it; with 2 the pointer draws nothing and the same
  #       clicks do nothing.
  #       No DOSBox mouse knob is needed on top of that: this dosbox-x
  #       build serves INT 33h out of the box. [sdl] autolock=true below
  #       is kept as in the other dosbox-x games here, so the first left
  #       click inside the window is swallowed to capture the pointer
  #       and the second one is the first the game sees - normal DOSBox
  #       behaviour, not a regression.
  #
  # The answers are typed with DOSBox-X `autotype` *before* -c "CIV.EXE",
  # which is what makes this deterministic rather than the timing race an
  # earlier attempt (autotype after the launch, waiting for each prompt to
  # appear) would have been:
  #
  #   - autotype keys land in the BIOS keyboard buffer at 0040:001E and
  #     CIV.EXE does not flush it, so keys that arrive before the game is
  #     even loaded simply wait there;
  #   - all three prompts are blocking console reads in a fixed order, so
  #     keys that arrive after a prompt is already on screen are consumed
  #     by that prompt.
  #
  # Both directions were measured on this asset: `-w 0 -p 0.05` (all
  # three keys queued before CIV.EXE finishes loading) and `-w 12 -p 1`
  # (keys delivered ~10s after the first prompt is already drawn) land
  # the same 1/6/1 answers. There is no window in which an answer can go
  # to the wrong prompt, so the pacing below is just breathing room.
  #
  # `CIV.EXE < answers.txt` looks tidier and does answer all three
  # prompts, but it is not usable: DOS stdin stays redirected afterwards,
  # so the intro polls the console, gets EOF instead of keys, and the
  # game wedges on the title screen forever.
  #
  # Civ writes its saves (CIVIL*.SVE / *.MAP) next to CIV.EXE, which the
  # per-game fuse-overlayfs upper persists.
  src = fetchIpfs {
    cid = "QmNkCCuK2wLfNStXm869SHyZjvFauNVCcw3Wc2qvBm9AGz";
    fallbackUrl = "https://archive.org/download/civ474.05/civ474.05.rar";
    hash = "sha256-dcIKuDakkgBVZvijhMi6Px87J2y3kwd/fWAyN1LHLfk=";
    name = "civilization-474.05-dos.rar";
  };

  dosboxConf = pkgs.writeText "dosbox.conf" ''
    [sdl]
    fullscreen=false
    output=opengl
    autolock=true
    showmenu=false

    [dosbox]
    machine=svga_s3
    memsize=16

    [render]
    aspect=true

    [cpu]
    core=auto
    cputype=auto
    cycles=auto

    [mixer]
    rate=44100

    [sblaster]
    sbtype=sb16
    sbbase=220
    irq=5
    dma=1

    [midi]
    mpu401=intelligent

    [dos]
    xms=true
    ems=true
    umb=true
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "civilization";

  inherit src;

  nativeBuildInputs = [
    unar
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/civ"
    unar -q -o "$TMPDIR/civ" "$src"
    gameroot=$(dirname "$(find "$TMPDIR/civ" -iname CIV.EXE -print -quit)")
    cp -r "$gameroot"/. "$out"/
    chmod -R u+w "$out"
  '';

  copyGlobs = [ ];

  runtime = "custom";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 640;
    nested-height = 480;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  runScript = ''
    exec ${dosbox-x}/bin/dosbox-x \
      -nomenu \
      -conf ${dosboxConf} \
      -c "mount c \"$GAMEDIR\"" \
      -c "c:" \
      -c "autotype -w 0 -p 0.3 1 6 1" \
      -c "CIV.EXE" \
      -c "exit" \
      -noconsole
  '';

  meta = {
    description = "Sid Meier's Civilization (MicroProse 1991 DOS, build 474.05, via DOSBox-X)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "civilization";
  };
}
