{
  self,
  lib,
  pkgs,
  fetchIpfs,
}:

let
  # Super Smash Bros. Melee (USA) (En,Ja) (v1.02). GameCube ISO,
  # 1459978240 bytes (1.36 GiB), the standard verified NTSC-U release.
  iso = fetchIpfs {
    cid = "QmNchGZ9oPDdv9DZjtXLkDnvyGoMsPY8rUAwY5eknYCbzb";
    fallbackUrl = "https://archive.org/download/super-smash-bros.-melee-usa-en-ja-v-1.02/Super%20Smash%20Bros.%20Melee%20%28USA%29%20%28En%2CJa%29%20%28v1.02%29.iso";
    hash = "sha256-DeBZgaNBVrnO3O9zxz1CRKwFz2FJqzyc/tkXaYgZ5GQ=";
    name = "super-smash-bros-melee.iso";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "super-smash-bros-melee";

  ipfsSources = [ iso ];
  src = iso;

  buildScript = ''
    mkdir -p "$out"
    cp "$src" "$out/melee.iso"
  '';

  runtime = "native";

  runScript = ''
    DOLPHIN_USER="$STROM_GAMEDIR/dolphin-user"
    mkdir -p "$DOLPHIN_USER/Config"

    # Skip the analytics opt-in dialog on first run. Dolphin auto-creates
    # the rest of Dolphin.ini and GCPadNew.ini on startup; its built-in
    # Linux keyboard defaults (A=X, B=Z, X=C, Y=S, Z=D, Start=Return,
    # arrows = stick, IJKL = C-stick, TFGH = D-pad, Q/W = L/R) bind to
    # the auto-detected XInput2 device, so keyboard works out of the box.
    # SIDevice0=6 (Standard Controller) is the default but pinned for
    # safety. Gamepads can be assigned in Options → Controllers.
    if ! [ -f "$DOLPHIN_USER/Config/Dolphin.ini" ]; then
      # Note: Dolphin's INI parser does NOT strip leading whitespace
      # (`if (line[0] == '[')` in IniFile::Load), so section headers
      # must start at column 0 — printf avoids the heredoc indent trap.
      printf '%s\n' \
        '[Analytics]' \
        'PermissionAsked = True' \
        'Enabled = False' \
        '[Core]' \
        'SIDevice0 = 6' \
        > "$DOLPHIN_USER/Config/Dolphin.ini"
    fi

    exec ${pkgs.gamescope}/bin/gamescope -W 1920 -H 1080 -r 60 --expose-wayland -- \
      ${pkgs.dolphin-emu}/bin/dolphin-emu \
        --user="$DOLPHIN_USER" \
        --batch \
        --exec="$GAMEDIR/melee.iso"
  '';

  meta = {
    description = "Super Smash Bros. Melee (via Dolphin)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "super-smash-bros-melee";
  };
}
