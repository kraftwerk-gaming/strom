{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Community "Complete Edition" repack by Rohankar (2026-02-27): base game
  # + Creature Isle expansion, pre-patched to v1.42 (unofficial fan patch)
  # and v1.23 (Creature Isle fan patch), with the 2018-rebuilt runblack.exe
  # that drops the original SafeDisc CD check.  Bundled `ddraw.dll` is
  # DDrawCompat v0.7.1 (statically-linked, loads itself as DDRAW.dll); it
  # patches the engine's d3d7 init so the title's well-known "white square"
  # / "black screen" bugs on modern drivers don't trigger.  The matching
  # `d3dim.dll` + `d3dim700.dll` stubs satisfy the DX7 retained-mode init.
  # The repack ships two .reg files: the plain Black_and_White_Registry_Fix
  # .reg (Windows-style HKLM paths) and Registry_Fix_For_Steam_Deck.reg
  # (HKCU paths that work inside a wine prefix without admin context) - we
  # apply the latter on first launch via seed-registry.py.
  src = fetchIpfs {
    cid = "QmbyH7EDnyttsXsebhCue2FgwNdJsWyn8AGK6iHURVrVbC";
    fallbackUrl = "https://archive.org/download/black-white-complete-edition/Black%20%26%20White%20-%20Complete%20Edition/Black%20%26%20White%20-%20Complete%20Edition.7z";
    hash = "sha256-Vf9jYQRqh3kRG4y0vo84SDIOHw3X9dJq/E+3+C77JyU=";
    name = "black-white-complete-edition.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "black-and-white";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  buildScript = ''
    mkdir -p "$out"
    7z x -o"$TMPDIR/bw" "$src"
    # Flatten the top-level "Black & White - Complete Edition/" dir into $out.
    # The two top-level .reg files (Black_and_White_Registry_Fix.reg,
    # Registry_Fix_For_Steam_Deck.reg) sit next to it in the 7z root; copy
    # the steam-deck one in too so the preRun script can find it without
    # a second fetch.
    cp -r "$TMPDIR/bw/Black & White - Complete Edition"/. "$out"/
    cp "$TMPDIR/bw/Registry_Fix_For_Steam_Deck.reg" "$out"/Registry_Fix_For_Steam_Deck.reg
    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper. The engine writes
  # under "$GAMEDIR/Profiles/<player>/Saved Games/" next to runblack.exe,
  # not under drive_c/users/steamuser/...; the fuse overlay's upper dir
  # (mounted from $STROM_GAMEDIR) keeps them across prefix wipes.
  saveLocations = [ ];

  executable = "runblack.exe";

  env = {
    # Use wine's builtin ddraw, not the bundled DDrawCompat ddraw.dll.
    # DDrawCompat is a Windows-only shim - on wine it loads, hooks
    # nothing useful (no display-mode/D3D-driver init lines appear in
    # its log), then immediately detaches, leaving the engine to call
    # a NULL vtable pointer right after DLL_PROCESS_ATTACH and crash
    # with EXCEPTION_ACCESS_VIOLATION at eip=00000000 (confirmed via
    # WINEDEBUG=+module,+process,+seh).  The Rohankar README's Steam
    # Deck instructions explicitly say `WINEDLLOVERRIDES="ddraw;
    # d3dim=n,b"` - i.e. an empty (= builtin) ddraw override and
    # native-first d3dim - which is what we mirror here.  d3dim700 has
    # no native winelib counterpart so we don't override it.
    WINEDLLOVERRIDES = "ddraw=b;d3dim=n,b";
  };

  preRun = ''
    # Seed the wineprefix registry with Rohankar's Steam-Deck reg fix
    # before proton bootstraps the prefix.  The engine reads HKCU\Software
    # \Lionhead Studios Ltd\Black & White\{GameDir,GameVersion,BWSetup\*}
    # at startup; without them runblack.exe exits silently right after
    # DDrawCompat detaches.  seed-registry.py parses the UTF-16 LE .reg
    # the repack ships, strips the HKEY_CURRENT_USER prefix, doubles each
    # backslash, stamps each section with a unix timestamp, and appends
    # the result to user.reg (creating a minimal header if absent so the
    # seed survives a clean first launch).
    ${pkgs.python3}/bin/python3 ${./seed-registry.py} \
      "$GAMEDIR/Registry_Fix_For_Steam_Deck.reg" \
      "$STROM_COMPATDATA/0/pfx/user.reg"
  '';

  gamescope = {
    # Black & White is a DirectDraw7-era 4:3 title.  Nest at the engine's
    # native 1024x768 and letterbox into the user's 1920x1080 monitor via
    # `--scaler fit` (preserves aspect; pillarboxes instead of stretching).
    # seed-registry.py rewrites ScreenW/ScreenH in the seeded .reg to match
    # this nested resolution so IDirectDraw7::SetDisplayMode(1024,768)
    # succeeds on the first try instead of falling back to 640x480 when
    # the repack's hard-coded 1280x800 mode isn't available from xwayland.
    output-width = 1920;
    output-height = 1080;
    nested-width = 1024;
    nested-height = 768;
    flags = {
      "-r" = "60";
      "-S" = "fit";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Black & White (Lionhead 2001, Complete Edition + v1.42 + Creature Isle v1.23, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "black-and-white";
  };
}
