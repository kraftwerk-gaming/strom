# Shared PCSX2 (PS2) game packaging helper.
#
# Provides the PS2 BIOS, a sane default PCSX2.ini, and a wrapper that
# wires everything together.  Individual games only need to supply
# { name, src, description } and, optionally, extra INI sections or a
# gamePath override (when src is a zip that needs extraction).
#
# Interface mirrors mkGame: self.lib.mkPcsx2Game { inherit lib pkgs; } { ... }
{
  lib,
  pkgs,
}:

let
  lassie = pkgs.callPackage ../pkgs/lassie.nix { };
  fetchIpfs = import ./fetch-ipfs.nix {
    inherit (pkgs)
      lib
      stdenvNoCC
      go-car
      curl
      cacert
      ;
    inherit lassie;
  };

  ps2bios = fetchIpfs {
    cid = "QmRJTnELYzS3JsxzPcNiPXpQgzpG65W9JMjniwm5SQx1be";
    fallbackUrl = "https://archive.org/download/ps2-0100j-20000117/ps2-0200a-20040614.bin";
    hash = "sha256-bSPQAdryoPqLOBpdSfUXU8NuNiLQ8EvkavGgxUi+R0Q=";
    name = "ps2-0200a-20040614.bin";
  };

  # BIOS dir with pregenerated .mec sidecar (4-byte version/region tag)
  biosDir = pkgs.runCommandLocal "ps2-bios" { } ''
    mkdir -p $out
    cp ${ps2bios} $out/ps2-0200a-20040614.bin
    printf '\x03\x06\x02\x00' > $out/ps2-0200a-20040614.mec
  '';

  basePcsx2Ini = ''
    [UI]
    SettingsVersion = 1
    SetupWizardIncomplete = false
    StartFullscreen = false
    HideMouseCursor = true
    HideMainWindowWhenRunning = true

    [Folders]
    Bios = ${biosDir}

    [EmuCore]
    EnableFastBoot = true
    EnableWideScreenPatches = true
    EnableGameFixes = true
    WarnAboutUnsafeSettings = false

    [EmuCore/GS]
    OsdShowMessages = false

    [Pad1]
    Up = SDL-0/DPadUp
    Right = SDL-0/DPadRight
    Down = SDL-0/DPadDown
    Left = SDL-0/DPadLeft
    Triangle = SDL-0/FaceNorth
    Circle = SDL-0/FaceEast
    Cross = SDL-0/FaceSouth
    Square = SDL-0/FaceWest
    Select = SDL-0/Back
    Start = SDL-0/Start
    L1 = SDL-0/LeftShoulder
    L2 = SDL-0/+LeftTrigger
    R1 = SDL-0/RightShoulder
    R2 = SDL-0/+RightTrigger
    L3 = SDL-0/LeftStick
    R3 = SDL-0/RightStick
    Analog = SDL-0/Guide
    LUp = SDL-0/-LeftY
    LRight = SDL-0/+LeftX
    LDown = SDL-0/+LeftY
    LLeft = SDL-0/-LeftX
    RUp = SDL-0/-RightY
    RRight = SDL-0/+RightX
    RDown = SDL-0/+RightY
    RLeft = SDL-0/-RightX
    LargeMotor = SDL-0/LargeMotor
    SmallMotor = SDL-0/SmallMotor

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
in

{
  name,
  src,
  description,
  gamePath ? "${src}",
  extraIni ? "",
}:

let
  pcsx2Ini = pkgs.writeText "PCSX2.ini" (basePcsx2Ini + extraIni);
in
(pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [ pkgs.pcsx2 ];
  meta = {
    inherit description;
    mainProgram = name;
    platforms = lib.platforms.linux;
  };
  text = ''
    DATADIR="''${HOME:-.}/.strom/${name}"
    PCSX2DIR="$DATADIR/config/PCSX2"
    mkdir -p "$PCSX2DIR/inis" "$PCSX2DIR/memcards" "$PCSX2DIR/sstates" "$PCSX2DIR/cache"

    # Always write config from nix (declarative)
    cp ${pcsx2Ini} "$PCSX2DIR/inis/PCSX2.ini"
    chmod 644 "$PCSX2DIR/inis/PCSX2.ini"

    export XDG_CONFIG_HOME="$DATADIR/config"

    exec pcsx2-qt \
      -batch \
      -fastboot \
      -- "${gamePath}"
  '';
}).overrideAttrs
  (_: {
    passthru = {
      runtime = "pcsx2";
      ipfsSources = [
        src
        ps2bios
      ];
    };
  })
