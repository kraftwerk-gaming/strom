{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
}:

let
  # GOG re-release of RollerCoaster Tycoon Deluxe v1.20: no-CD, includes
  # both Corkscrew Follies and Loopy Landscapes. Ships as a zip with the
  # GOG Inno Setup installer (.exe stub + .bin slot 1).
  src = fetchIpfs {
    cid = "QmR3NEi1oBN3sNtc3RCyWtGncwnf6MiWx54gtx1hUiNyBN";
    fallbackUrl = "https://archive.org/download/roller-coaster-tycoon-deluxe-v-1.20-gog/RollerCoaster%20Tycoon%20Deluxe%20v1.20%20%5BGOG%5D.zip";
    hash = "sha256-D+mRGo+r98A6WO0IYE5aMQsO0LiGdI05VkAASfySRn4=";
    name = "rollercoaster-tycoon-deluxe-gog.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "rollercoaster-tycoon";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    cd "$TMPDIR/zip/RollerCoaster Tycoon Deluxe v1.20 [GOG]"
    innoextract --gog -d "$TMPDIR/iss" "Setup_RollerCoaster_Tycoon_Deluxe_v1.20_GOG_v3(86337).exe"
    # The GOG installer drops game files at the extraction root; the
    # tmp/, app/, commonappdata/, __redist/ subtrees are install-time
    # scaffolding we don't need at runtime.
    cp "$TMPDIR/iss/RCT.EXE" "$out/"
    cp "$TMPDIR/iss/ddraw.dll" "$out/"
    cp -r "$TMPDIR/iss/Data" "$out/"
    cp -r "$TMPDIR/iss/Tracks" "$out/"
    cp -r "$TMPDIR/iss/Scenarios" "$out/"
    cp -r "$TMPDIR/iss/Saved Games" "$out/"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # Data/*.DAT + Data/Game.cfg next to its binary, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "RCT.EXE";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  env = {
    # The GOG release ships its own ddraw.dll (a cnc-ddraw / DDrawCompat
    # style shim that fixes Win10+ DirectDraw rendering and the CD check).
    # Tell Wine to load this native DLL before its built-in ddraw.
    WINEDLLOVERRIDES = "ddraw=n,b";
  };

  # The GOG installer normally writes a handful of HKCU registry values
  # under "Fish Technology Group\\RollerCoaster Tycoon Setup" — the game
  # reads Path/SetupPath/Executable/AddOn from there and falls back to
  # asking for the CD when they're missing.
  #
  # These are appended directly as Wine registry text (no regedit /
  # PROTON_RUN, which is not exported at preRun time). proton creates the
  # prefix on first launch, so on a truly fresh prefix user.reg does not
  # exist yet and that first launch comes up without the keys; they land on
  # the next launch once proton has bootstrapped the prefix, and persist.
  # GAMEDIR_WIN is the in-prefix Z: path mapping to the fuse-overlayfs
  # $GAMEDIR. RCT.EXE is a 32-bit Win9x-era app, so on a win64 prefix its
  # HKCU\Software reads are redirected to HKCU\Software\Wow6432Node; the key
  # is written to both views so the engine resolves it either way.
  preRun = ''
    USERREG="$STROM_COMPATDATA/0/pfx/user.reg"
    if [ -f "$USERREG" ] \
        && ! grep -q 'Fish Technology Group\\\\RollerCoaster Tycoon Setup' "$USERREG"; then
      echo "[strom] first-run setup: seeding RollerCoaster Tycoon Setup registry"
      GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}"
      TS=$(date +%s)
      for base in \
        'Software\\Fish Technology Group' \
        'Software\\Wow6432Node\\Fish Technology Group'; do
        {
          printf '\n[%s\\\\RollerCoaster Tycoon Setup] %s\n' "$base" "$TS"
          printf '"Title"="Roll"\n'
          printf '"Path"="%s"\n' "$GAMEDIR_WIN"
          printf '"SetupPath"="%s"\n' "$GAMEDIR_WIN"
          printf '"Executable"="rct.exe"\n'
          printf '"FontPointSize"=dword:0000000c\n'
          printf '"Language"=dword:00000000\n'
          printf '"CDKey"=dword:00000000\n'
          printf '"CharSet"=dword:00000000\n'
          printf '"FontFaceName"="MS Sans Serif"\n'
          printf '"OKPrompt"="OK"\n'
          printf '"CancelPrompt"="Cancel"\n'
          printf '"AddOn"=dword:00000001\n'
        } >>"$USERREG"
      done
    fi
  '';

  meta = {
    description = "RollerCoaster Tycoon Deluxe (GOG v1.20, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rollercoaster-tycoon";
  };
}
