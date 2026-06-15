{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # CONSCRIPT (Catchweight Studio / Team17, 2024) -- WW1 survival-horror
  # built on GameMaker (GMS2 runner: CONSCRIPT.exe + data.win +
  # audiogroup*.dat). No native Linux build ships, so runtime = "proton".
  #
  # SteamGG.NET pre-installed repack of the v1.0.0.2 Windows build. The
  # archive is a single top-level dir "CONSCRIPT - SteamGG.NET/" holding
  # the runner plus a RUNE Steam emulator: steam_api64.dll is the RUNE
  # crack (with its steam_api64.rne config blob and steam_emu.ini pinning
  # AppId=1286990), so it boots offline with no Steam client / login. The
  # GameMaker name embedded in data.win's GEN8 chunk is "CONSCRIPT", which
  # is the %LOCALAPPDATA% folder the runner writes its save into.
  #
  # Source: pixeldrain mirror (clean direct API, range-capable) linked
  # from steamgg.net's CONSCRIPT page. The buzzheavier and datanodes
  # mirrors on the same page sit behind a Cloudflare challenge, and the
  # steamrip primary (megadb) is countdown/captcha-walled, so pixeldrain
  # is the only headless-reachable direct URL.
  src = fetchIpfs {
    cid = "QmVDEti49XpZUBkJBbjGW6ZZh7UzJFs4w6ovaqokCPPeng";
    fallbackUrl = "https://pixeldrain.com/api/file/bhL1wZGV?download";
    hash = "sha256-9WI7uNZ4AbBA4/mE/9q23PWrZl+u0VxLLFQ0V0qNIa0=";
    name = "conscript.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "conscript";

  ipfsSources = [ src ];
  inherit src;

  nativeBuildInputs = [ unzip ];

  # Strip the "CONSCRIPT - SteamGG.NET/" wrapper so CONSCRIPT.exe sits at
  # $out root next to data.win, the audiogroup*.dat banks, Fonts/,
  # Localization/, and the RUNE steam_api64.dll. Drop the repack's
  # marketing shortcut, the bundled redistributables (Proton's prefix
  # already has the runtime the GameMaker runner needs), and the bundled
  # wallpapers -- none are needed to launch.
  buildScript = ''
    mkdir -p "$out"
    # The repack's "SteamGG ... .url" shortcut carries a UTF-8 en-dash the
    # sandbox's C locale can't reconcile between the zip's local and
    # central filename records, so unzip warns and exits non-zero even
    # though every game file extracts fine; tolerate it (the .url is
    # dropped below anyway).
    unzip -q "$src" -d "$TMPDIR/extract" || true
    cp -r "$TMPDIR/extract/CONSCRIPT - SteamGG.NET/." "$out"/
    rm -rf "$out/_Redist" "$out/CONSCRIPT - Wallpapers" "$out"/*.url
    test -f "$out/CONSCRIPT.exe" \
      || { echo "CONSCRIPT.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/data.win" \
      || { echo "data.win missing from extracted tree" >&2; exit 1; }
    test -f "$out/steam_api64.dll" \
      || { echo "steam_api64.dll (RUNE emu) missing" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "CONSCRIPT.exe";

  # GameMaker writes its local save to %LOCALAPPDATA%\CONSCRIPT (the GEN8
  # game name). The RUNE emulator additionally mirrors Steam RemoteStorage
  # under Users\Public\Documents\Steam\RUNE\1286990, which lives outside
  # the steamuser tree saveLocations can reach; preRun symlinks that path
  # into the steamuser profile so it's relocated and survives prefix wipes
  # too.
  saveLocations = [
    "AppData/Local/CONSCRIPT"
    "rune-cloud-save"
  ];

  preRun = ''
    __pfx="$STROM_COMPATDATA/0/pfx/drive_c"
    __rune="$__pfx/users/Public/Documents/Steam/RUNE/1286990"
    __target="$__pfx/users/steamuser/rune-cloud-save"
    mkdir -p "$__target" "$(dirname "$__rune")"
    if [ -e "$__rune" ] && [ ! -L "$__rune" ]; then
      cp -an "$__rune/." "$__target/" 2>/dev/null || true
      rm -rf "$__rune"
    fi
    ln -snf "$__target" "$__rune"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--immediate-flips" = true;
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "CONSCRIPT (Catchweight Studio / Team17 2024, WW1 survival-horror, GameMaker / Windows via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "conscript";
  };
}
