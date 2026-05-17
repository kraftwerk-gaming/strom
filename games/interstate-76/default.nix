{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  innoextract,
  python3,
}:

let
  # archive.org mirror of the GOG "Interstate '76 Arsenal" pack: outer
  # zip wraps the GOG Inno Setup installer (setup_interstate76_arsenal.exe),
  # which bundles both the base game (app/interstate 76/i76.exe) and the
  # Nitro Pack expansion (app/Interstate 76 Nitro Pack/nitro.exe).
  src = fetchIpfs {
    cid = "Qma3cbzkU4FucWUeNY1cfgzFML3G6XPoWr1HKYGMNdQCWh";
    fallbackUrl = "https://archive.org/download/interstate-76-arsenal-gog.com-version/Interstate%20%2776%20Arsenal%20%5BGOG.com%20Version%5D.zip";
    hash = "sha256-up66OUybQFMB9sp0++p82DLj6pjFO8cWBCoJ1I1uzws=";
    name = "interstate-76.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "interstate-76";

  inherit src;

  nativeBuildInputs = [
    unzip
    innoextract
    python3
  ];

  # Unwrap outer GOG bundle zip, then run innoextract on the GOG
  # Inno Setup installer. app/ contains "interstate 76" (base game) and
  # "Interstate 76 Nitro Pack" (expansion). Promote the base game to the
  # overlay root so i76.exe sits next to its data files. The Nitro Pack
  # stays at its full path under "Interstate 76 Nitro Pack/" for anyone
  # who wants to switch the executable. After extraction, patch-i76.py
  # patches i76.exe with three independent fixes (CD-2 bypass, CPU-speed
  # crash, 25fps frame cap) — see that file for details.
  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$TMPDIR/zip"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/zip/Interstate '76 Arsenal [GOG.com Version]/setup_interstate76_arsenal.exe"
    cp -r "$TMPDIR/iss/app/interstate 76"/. "$out"/
    cp -r "$TMPDIR/iss/app/Interstate 76 Nitro Pack" "$out/Interstate 76 Nitro Pack"
    if [ -f "$TMPDIR/iss/app/Manual.pdf" ]; then
      cp "$TMPDIR/iss/app/Manual.pdf" "$out/Manual.pdf"
    fi
    chmod +w "$out/i76.exe"
    python3 ${./patch-i76.py} "$out/i76.exe"
    chmod -w "$out/i76.exe"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (engine writes
  # *.fot save files + I76*.DEF config + ADDON/ next to its binary, not
  # under drive_c/users/steamuser/...).
  saveLocations = [ ];
  # i76.exe is the base-game entry. The GOG bundle also ships
  # Interstate 76 Nitro Pack/nitro.exe for the expansion missions.
  executable = "i76.exe";

  # The patched scan functions report the CD as drive E:, so the game
  # then reads SMK movies / mission data through e:\smk\..., e:\miss16\..,
  # etc. Mirror those paths via a dosdevices symlink to the install dir
  # (which already contains the same files that used to ship on disc 2).
  preRun = ''
    pfx="$STROM_COMPATDATA/0/pfx"
    mkdir -p "$pfx/dosdevices"
    ln -snf "$GAMEDIR" "$pfx/dosdevices/e:"
  '';

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
    description = "Interstate '76 Arsenal (Activision 1997, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "interstate-76";
  };
}
