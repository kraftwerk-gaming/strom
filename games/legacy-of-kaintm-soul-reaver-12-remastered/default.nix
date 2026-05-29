{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Legacy of Kain(TM) Soul Reaver 1+2 Remastered (Crystal Dynamics /
  # Aspyr, Dec 2024). GOG product 1214553287, build buildId=58163442642617146
  # (matches GOG v1.01). The source is a "preinstalled" 7z dump of the
  # GOG install tree carried on archive.org; it contains the GOG Galaxy
  # support DLLs (Galaxy64.dll, steam_api64.dll) and the goggame-*.info /
  # .script / .hashdb metadata that the GOG installer would have written.
  # Galaxy is optional for play -- the game launches against the offline
  # fallback when Galaxy is absent, which is the path used here.
  #
  # The upload notes that the bundle is intended for the uploader's
  # "Central Arquivista" front-end, but inspection of the tree shows it
  # is a stock GOG install tree (no rewritten launchers, no extra hooks):
  # SRX.exe is the unmodified Aspyr launcher and `playTasks[0].path` in
  # goggame-1214553287.info points at it directly.
  src = fetchIpfs {
    cid = "QmepRDNXxVXbHCMDM2g2JqMwXXMoQx2m58zpze75yRMjX7";
    fallbackUrl = "https://archive.org/download/CA-WINDOWS-Soul-Reaver-1-and-2-Remastered/Soul%20Reaver%201%20and%202%20-%20Remastered.7z";
    hash = "sha256-BMX8QlY6jqFho2uzj8GTUXZZ8Tb1RvEsduAjpU1EOcI=";
    name = "soul-reaver-1-2-remastered.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "legacy-of-kaintm-soul-reaver-12-remastered";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  # Archive root is a single directory "Soul Reaver 1 and 2 - Remastered/"
  # containing the game tree. Lift its contents into $out and drop the
  # GOG installer scaffolding (uninstaller, .lnk shortcut, support icon,
  # webcache zip, goglog) that the engine never touches. Keep the
  # goggame-*.{info,script,hashdb} files: they are read by SRX.exe's
  # offline fallback to resolve the save folder layout.
  buildScript = ''
    mkdir -p "$out"
    7z x -y -bsp0 -bso0 "$src" -o"$TMPDIR/7z"
    cp -r "$TMPDIR/7z/Soul Reaver 1 and 2 - Remastered"/. "$out"/
    chmod -R u+w "$out"

    rm -f "$out/unins000.exe" "$out/unins000.dat" "$out/unins000.ini" \
      "$out/unins000.msg" "$out/support.ico" "$out/webcache.zip" \
      "$out/goglog.ini" "$out"/Launch\ Legacy\ of\ Kain*.lnk || true

    test -f "$out/SRX.exe" \
      || { echo "SRX.exe missing from extracted tree" >&2; exit 1; }
    test -f "$out/1/sr1.dll" \
      || { echo "1/sr1.dll missing from extracted tree" >&2; exit 1; }
    test -f "$out/2/sr2.dll" \
      || { echo "2/sr2.dll missing from extracted tree" >&2; exit 1; }
  '';

  runtime = "proton";
  executable = "SRX.exe";

  # GOG metadata (goggame-1214553287.script) declares the save folder as
  # "{userappdata}/../Roaming/SRX/" -- i.e. %APPDATA%/SRX -- which lands
  # at AppData/Roaming/SRX under drive_c/users/steamuser/. Best guess
  # pending post-launch sweep; confirm with the `find -newer` check in
  # AGENTS.md after first interactive run.
  saveLocations = [ "AppData/Roaming/SRX" ];

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

  meta = {
    description = "Legacy of Kain Soul Reaver 1+2 Remastered (Crystal Dynamics / Aspyr 2024, GOG v1.01, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "legacy-of-kaintm-soul-reaver-12-remastered";
  };
}
