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
    [Pad1]
    Up = SDL-0/DPadUp & SDL-1/DPadUp
    Right = SDL-0/DPadRight & SDL-1/DPadRight
    Down = SDL-0/DPadDown & SDL-1/DPadDown
    Left = SDL-0/DPadLeft & SDL-1/DPadLeft
    Triangle = SDL-0/FaceNorth & SDL-1/FaceNorth
    Circle = SDL-0/FaceEast & SDL-1/FaceEast
    Cross = SDL-0/FaceSouth & SDL-1/FaceSouth
    Square = SDL-0/FaceWest & SDL-1/FaceWest
    Select = SDL-0/Back & SDL-1/Back
    Start = SDL-0/Start & SDL-1/Start
    L1 = SDL-0/LeftShoulder & SDL-1/LeftShoulder
    L2 = SDL-0/+LeftTrigger & SDL-1/+LeftTrigger
    R1 = SDL-0/RightShoulder & SDL-1/RightShoulder
    R2 = SDL-0/+RightTrigger & SDL-1/+RightTrigger
    L3 = SDL-0/LeftStick & SDL-1/LeftStick
    R3 = SDL-0/RightStick & SDL-1/RightStick
    Analog = SDL-0/Guide & SDL-1/Guide
    LUp = SDL-0/-LeftY & SDL-1/-LeftY
    LRight = SDL-0/+LeftX & SDL-1/+LeftX
    LDown = SDL-0/+LeftY & SDL-1/+LeftY
    LLeft = SDL-0/-LeftX & SDL-1/-LeftX
    RUp = SDL-0/-RightY & SDL-1/-RightY
    RRight = SDL-0/+RightX & SDL-1/+RightX
    RDown = SDL-0/+RightY & SDL-1/+RightY
    RLeft = SDL-0/-RightX & SDL-1/-RightX
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
