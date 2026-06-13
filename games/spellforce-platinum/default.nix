{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # GOG "SpellForce Platinum Edition" offline installer v2.0.0.8
  # (setup_spellforce_platinum_2.0.0.8.exe + -1.bin + -2.bin, ~2.4 GB).
  # Source: freegogpcgames magnet btih:1C97308DA2406BDD0B5F45EF476465EB33B3F3B4
  # Tar bundles all three installer parts; innoextract handles split .bin
  # automatically when all parts share the same directory.
  # No fallbackUrl: this tar is repacked locally from the magnet's installer
  # parts (above), so no public URL serves these exact bytes -- IPFS is the
  # canonical source. Rebuild from the magnet + `tar` if the pin is ever lost.
  src = fetchIpfs {
    cid = "QmStWVhi1QxkM7UPe3vgZxpnGFsEGP6HUTUKgiUtbUugpK";
    hash = "sha256-vleekkj/G9/YdLNHD7qFKn9lORT27gU3RiO2Y/klaAI=";
    name = "spellforce-platinum-gog.tar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "spellforce-platinum";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/gog"
    tar -xf "$src" -C "$TMPDIR/gog"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/gog"/setup_spellforce_platinum_*.exe
    cp -r "$TMPDIR/iss/app"/. "$out"/
    chmod -R u+w "$out"
    rm -f "$out/goggame-"*.dll "$out/goggame-"*.info "$out/goggame-"*.hashdb
  '';

  runtime = "proton";
  executable = "SpellForce.exe";

  # SpellForce.exe shows a "PLEASE ENTER THE SERIAL NUMBER (MAIN GAME)"
  # dialog over the main menu on a fresh prefix. Driving the dialog under
  # Proton and diffing the prefix registry before/after acceptance proves
  # the runtime check honours exactly one REG_SZ value:
  #   [Software\Wow6432Node\Microsoft\Windows\CurrentVersion\
  #      Uninstall\SpellForce]  "CDKEY"="<key>"   (REG_SZ)
  # SpellForce.exe is 32-bit, so under 64-bit Proton the HKLM\SOFTWARE
  # write lands in the Wow6432Node view of system.reg. The game itself
  # creates that subkey on launch with empty CDKEY/CDKEY1/CDKEY2; only
  # CDKEY is read for the main game, and the validator REJECTS arbitrary
  # strings ("Invalid serial number"). The accepted key is the official
  # one the developers published for the GOG/Steam legacy 1.54 branch
  # (= this Platinum build): 4Y7YP-5E7U3-2UWR5-GT0KM-ZDAJI.
  #
  # Proton creates system.reg only AFTER preRun on a fresh prefix, so seed
  # the value before the first launch. The hive header MUST be the exact
  # win64 form proton writes ("REGISTRY\\Machine" + "#arch=win64"); the
  # earlier seed used a "\\Machine"/no-arch header, which made wine treat
  # the prefix as 32-bit and abort ("32-bit installation, cannot support
  # 64-bit applications"). With the correct header proton merges the
  # pre-seeded value into the prefix it builds, so launch goes straight to
  # the menu with no prompt. On an existing prefix, just point the game's
  # own CDKEY at the accepted value (rewrite in place or append the subkey).
  preRun = ''
    SYSREG="$STROM_COMPATDATA/0/pfx/system.reg"
    SFKEY=4Y7YP-5E7U3-2UWR5-GT0KM-ZDAJI
    mkdir -p "$(dirname "$SYSREG")"
    if [ ! -f "$SYSREG" ]; then
      printf 'WINE REGISTRY Version 2\n;; All keys relative to REGISTRY\\\\Machine\n\n#arch=win64\n' > "$SYSREG"
    fi
    if grep -q '"CDKEY"=' "$SYSREG"; then
      sed -i "s/^\"CDKEY\"=\".*\"\$/\"CDKEY\"=\"$SFKEY\"/" "$SYSREG"
    elif ! grep -q 'CurrentVersion\\\\Uninstall\\\\SpellForce' "$SYSREG"; then
      {
        printf '\n[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall\\\\SpellForce] %s\n' "$(date +%s)"
        printf '"CDKEY"="%s"\n' "$SFKEY"
      } >> "$SYSREG"
    fi
  '';

  # SpellForce writes savegames + config under My Documents\SpellForce\.
  # The GOG Platinum build keeps the base-game tree (the addons reuse the
  # same save directory). Relocate it so wineprefix wipes don't lose
  # progress. VERIFY against the real install once sourced.
  saveLocations = [ "Documents/SpellForce" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Confine the pointer to the window (relative mouse mode). Without
      # this the RTS edge-scrolling goes erratic once the cursor leaves
      # the game window -- same flag every other strategy game here uses.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "SpellForce Platinum Edition (Phenomic / JoWooD 2003-2004: The Order of Dawn + Breath of Winter + Shadow of the Phoenix, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "spellforce-platinum";
  };
}
