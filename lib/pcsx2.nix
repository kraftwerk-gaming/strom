# pcsx2 wrapperModule (raw module source).
#
# Wraps PCSX2-Qt for PS2 emulation. Materializes a PCSX2.ini at runtime
# under $STROM_GAMEDIR/config/PCSX2/inis (chmod 644 so the in-emulator UI
# can edit it). The wrapped binary IS pcsx2-qt; the iso path is a typed
# option appended as the final positional argument.
#
# Usage as a sub-option submodule:
#   lib.types.submoduleWith {
#     specialArgs = { inherit wlib; };
#     modules = [ wlib.modules.wrapper wlib.modules.meta (import ./pcsx2.nix) ];
#   }
{
  config,
  lib,
  fetchIpfs,
  ...
}:
let
  inherit (lib) mkOption types;

  # PS2 BIOS shared across all pcsx2 games. The .mec sidecar is PCSX2's
  # region/version cache; pre-generating it skips the first-run BIOS scan
  # dialog.
  defaultBios = fetchIpfs {
    cid = "QmRJTnELYzS3JsxzPcNiPXpQgzpG65W9JMjniwm5SQx1be";
    fallbackUrl = "https://archive.org/download/ps2-0100j-20000117/ps2-0200a-20040614.bin";
    hash = "sha256-bSPQAdryoPqLOBpdSfUXU8NuNiLQ8EvkavGgxUi+R0Q=";
    name = "ps2-0200a-20040614.bin";
  };
  defaultBiosDir = config.pkgs.runCommandLocal "ps2-bios" { } ''
    mkdir -p $out
    cp ${config.bios} $out/ps2-0200a-20040614.bin
    printf '\x03\x06\x02\x00' > $out/ps2-0200a-20040614.mec
  '';

  basePcsx2Ini = ''
    [UI]
    SettingsVersion = 1
    SetupWizardIncomplete = false
    StartFullscreen = true
    HideMouseCursor = true
    HideMainWindowWhenRunning = true

    [Folders]
    Bios = ${config.biosDir}

    [EmuCore]
    EnableFastBoot = true
    EnableWideScreenPatches = true
    EnableGameFixes = true
    WarnAboutUnsafeSettings = false

    [EmuCore/GS]
    OsdShowMessages = false

    # Bind both SDL-0 and SDL-1 because SDL's controller enumeration can
    # put a real gamepad at index 1 when motion sensors or virtual devices
    # grab index 0. PCSX2 ORs the bindings, so whichever index the actual
    # controller ends up on works.
    #
    # Keyboard is ORed in alongside the pad (same `&` mechanism), NOT as an
    # alternative to it: both are live at once, so a PS2 game is playable
    # with no controller attached and a pad still works the moment one is
    # plugged in. Without this the whole [Pad1] section was SDL-only and
    # every PS2 title was unplayable on a keyboard-only machine.
    #
    # The key names are PCSX2's OWN generic keyboard defaults, lifted from
    # InputManager.cpp's AddGenericBindings (Cross=K, Circle=L, Square=J,
    # Triangle=I, Start=Return, Select=Backspace, left stick WASD, right
    # stick TFGH, L1/R1=Q/E, L2/R2=1/3, L3/R3=2/4), so muscle memory and
    # every PCSX2 guide on the internet match. Names are the Qt key
    # spellings from pcsx2-qt/QtKeyCodes.cpp.
    [Pad1]
    Up = SDL-0/DPadUp & SDL-1/DPadUp & Keyboard/Up
    Right = SDL-0/DPadRight & SDL-1/DPadRight & Keyboard/Right
    Down = SDL-0/DPadDown & SDL-1/DPadDown & Keyboard/Down
    Left = SDL-0/DPadLeft & SDL-1/DPadLeft & Keyboard/Left
    Triangle = SDL-0/FaceNorth & SDL-1/FaceNorth & Keyboard/I
    Circle = SDL-0/FaceEast & SDL-1/FaceEast & Keyboard/L
    Cross = SDL-0/FaceSouth & SDL-1/FaceSouth & Keyboard/K
    Square = SDL-0/FaceWest & SDL-1/FaceWest & Keyboard/J
    Select = SDL-0/Back & SDL-1/Back & Keyboard/Backspace
    Start = SDL-0/Start & SDL-1/Start & Keyboard/Return
    L1 = SDL-0/LeftShoulder & SDL-1/LeftShoulder & Keyboard/Q
    L2 = SDL-0/+LeftTrigger & SDL-1/+LeftTrigger & Keyboard/1
    R1 = SDL-0/RightShoulder & SDL-1/RightShoulder & Keyboard/E
    R2 = SDL-0/+RightTrigger & SDL-1/+RightTrigger & Keyboard/3
    L3 = SDL-0/LeftStick & SDL-1/LeftStick & Keyboard/2
    R3 = SDL-0/RightStick & SDL-1/RightStick & Keyboard/4
    Analog = SDL-0/Guide & SDL-1/Guide
    LUp = SDL-0/-LeftY & SDL-1/-LeftY & Keyboard/W
    LRight = SDL-0/+LeftX & SDL-1/+LeftX & Keyboard/D
    LDown = SDL-0/+LeftY & SDL-1/+LeftY & Keyboard/S
    LLeft = SDL-0/-LeftX & SDL-1/-LeftX & Keyboard/A
    RUp = SDL-0/-RightY & SDL-1/-RightY & Keyboard/T
    RRight = SDL-0/+RightX & SDL-1/+RightX & Keyboard/H
    RDown = SDL-0/+RightY & SDL-1/+RightY & Keyboard/G
    RLeft = SDL-0/-RightX & SDL-1/-RightX & Keyboard/F
    LargeMotor = SDL-0/LargeMotor & SDL-1/LargeMotor
    SmallMotor = SDL-0/SmallMotor & SDL-1/SmallMotor

    [EmuCore/Speedhacks]
    EECycleRate = 0
    EECycleSkip = 0
    fastCDVD = false
    IntcStat = true
    WaitLoop = true
    vuFlagHack = false
    vuThread = true
    vu1Instant = true

    [EmuCore/CPU/Recompiler]
    EnableEE = true
    EnableIOP = true
    EnableEECache = false
    EnableVU0 = true
    EnableVU1 = true
    vu0Overflow = true
    vu0ExtraOverflow = true
    vu0SignOverflow = true
    vu0Underflow = true
    vu1Overflow = true
    vu1ExtraOverflow = true
    vu1SignOverflow = true
    vu1Underflow = true
    fpuOverflow = true
    fpuExtraOverflow = true
    fpuFullMode = true

    [EmuCore/GS]
    upscale_multiplier = 2
    accurate_blending_unit = 1
    UserHacks_DisableRenderFixes = false
  '';

  pcsx2Ini = config.pkgs.writeText "PCSX2.ini" (basePcsx2Ini + config.extraIni);
in
{
  _class = "wrapper";

  options = {
    bios = mkOption {
      type = types.package;
      default = defaultBios;
      description = ''
        PS2 BIOS .bin file. Default is a fetchIpfs'd dump. mkGame reads
        `cfg.pcsx2.bios` for its passthru.ipfsSources so the BIOS gets
        pinned alongside the game's src.
      '';
    };

    biosDir = mkOption {
      type = types.package;
      default = defaultBiosDir;
      description = ''
        Directory containing the PS2 BIOS .bin + .mec sidecar; written
        into PCSX2.ini's [Folders] Bios = section.
      '';
    };

    extraIni = mkOption {
      type = types.lines;
      default = "";
      description = "Extra PCSX2.ini fragments appended to the base ini (per-game tweaks).";
    };

    isoPath = mkOption {
      type = types.str;
      description = "Path to the game ISO. May contain shell variables (e.g. $STROM_OVERLAY/foo.iso).";
    };
  };

  config = {
    package = config.pkgs.pcsx2;
    exePath = "${config.pkgs.pcsx2}/bin/pcsx2-qt";
    binName = lib.mkDefault "pcsx2";

    env = {
      XDG_CONFIG_HOME = "$STROM_GAMEDIR/config";
      # Force PCSX2-Qt onto the X11/xcb backend. Its wayland backend renders
      # the game display into a Qt subsurface, which gamescope's compositor
      # doesn't support ("Can't create subsurface") -> grey screen + VM stall.
      # xcb runs it through gamescope's nested Xwayland, which works.
      QT_QPA_PLATFORM = "xcb";
    };

    preHook = ''
      mkdir -p "$STROM_GAMEDIR/config/PCSX2/inis" \
               "$STROM_GAMEDIR/config/PCSX2/memcards" \
               "$STROM_GAMEDIR/config/PCSX2/sstates" \
               "$STROM_GAMEDIR/config/PCSX2/cache"
      # Always write config from nix (declarative); chmod so the user can
      # edit one-shot settings via the in-emulator UI without being blocked
      # by the read-only nix store source.
      cp ${pcsx2Ini} "$STROM_GAMEDIR/config/PCSX2/inis/PCSX2.ini"
      chmod 644 "$STROM_GAMEDIR/config/PCSX2/inis/PCSX2.ini"
    '';

    args = [
      "-batch"
      "-fastboot"
      "--"
      config.isoPath
    ];
  };
}
