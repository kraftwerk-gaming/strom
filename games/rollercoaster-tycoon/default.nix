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
    SteamAppId = "0";
    SteamGameId = "0";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    # 32-bit Wine binary needs /usr/lib32 visible so DXVK can dlopen
    # libvulkan.so.1.
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # The GOG release ships its own ddraw.dll (a cnc-ddraw / DDrawCompat
    # style shim that fixes Win10+ DirectDraw rendering and the CD check).
    # Tell Wine to load this native DLL before its built-in ddraw.
    WINEDLLOVERRIDES = "ddraw=n,b";
  };

  # The GOG installer normally writes a handful of HKCU registry values
  # under "Fish Technology Group\\RollerCoaster Tycoon Setup" — the game
  # reads Path/SetupPath/Executable/AddOn from there and falls back to
  # asking for the CD when they're missing. Inject them on every launch
  # because $GAMEDIR (the overlay) is a fresh path each run.
  preRun = ''
    GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}"
    cat > "$GAMEDIR/rct-setup.reg" <<EOF
    Windows Registry Editor Version 5.00

    [HKEY_CURRENT_USER\\Software\\Fish Technology Group\\RollerCoaster Tycoon Setup]
    "Title"="Roll"
    "Path"="$GAMEDIR_WIN"
    "SetupPath"="$GAMEDIR_WIN"
    "Executable"="rct.exe"
    "FontPointSize"=dword:0000000c
    "Language"=dword:00000000
    "CDKey"=dword:00000000
    "CharSet"=dword:00000000
    "FontFaceName"="MS Sans Serif"
    "OKPrompt"="OK"
    "CancelPrompt"="Cancel"
    "AddOn"=dword:00000001
    EOF
    # The proton wrapper ends with `kill -9 0`, which would tear down the
    # whole process group. Run it under setsid so only the regedit
    # subprocess gets killed, and the main game launch proceeds.
    setsid "$PROTON_RUN" regedit /S "$GAMEDIR\\rct-setup.reg" || true
  '';

  meta = {
    description = "RollerCoaster Tycoon Deluxe (GOG v1.20, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "rollercoaster-tycoon";
  };
}
