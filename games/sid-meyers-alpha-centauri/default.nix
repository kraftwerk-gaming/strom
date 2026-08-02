{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unzip,
}:

let
  # Sid Meier's Alpha Centauri - Planetary Pack (Firaxis 1999): SMAC plus the
  # Alien Crossfire (SMACX) expansion. terranx.exe imports DirectDrawCreate +
  # DirectDrawEnumerateA straight from DDRAW.dll, so rendering runs on Wine's
  # builtin ddraw on top of wined3d. (There is no such thing as a DXVK ddraw
  # to swap in: files/lib/wine/dxvk ships only d3d8/d3d9/d3d10core/d3d11/dxgi
  # -- checked on both GE-Proton10-34 and GE-Proton11-1.)
  #
  # WHY NOT THE GOG INSTALLER. This package used to fetch
  # setup_sid_meiers_alpha_centauri_2.0.2.23.exe and innoextract --gog it.
  # Those bytes are not reachable without a logged-in GOG session, so the FOD
  # could only ever be realized by whoever hand-dropped the file into their
  # store. Re-verified before switching: archive.org has no
  # setup_sid_meiers_alpha_centauri_* item (the same identifier query does hit
  # setup_sid_meiers_pirates_2.0.0.4 and setup_sid_meiers_railroads_2.0.0.6,
  # so the naming scheme is right and the title is simply absent), searches
  # for gogrepo dumps and `identifier:(gog*) AND "alpha centauri"` return
  # nothing, and the "GOG free download" mirrors (gog-games.to, gogunlocked,
  # gametrex) gate every link behind JS/Turnstile with no URL in the served
  # HTML. The GOG release magnet, kept for provenance only, was
  # magnet:?xt=urn:btih:20AE9BF80FEABF6B8E1CCF7B5A6F130B5785C065
  #   &dn=sid+meiers+alpha+centauri+planetary+pack+gog
  # and the installer it names hashes to
  # sha256-ovE6vQtPIBsDDBX5Tp1Dn2WTiti3R0sXHj6/7xzH+lE=.
  #
  # The retail Planetary Pack disc carries the data, and the executable comes
  # from Yitzi's patch below, because the disc's own binaries are SafeDisc:
  # programs/terran.exe and programs/terranx.exe are both 249119-byte loader
  # stubs whose real code sits in encrypted programs/Terran.icd (2932781 B) /
  # programs/Terranx.icd (3076141 B), which want the physical disc plus
  # secdrv.sys and cannot run under Proton at all. Everything else on the disc
  # is stored plainly (993 files under programs/, plus fx/, voices/, movies/),
  # so only the executable has to be replaced.
  iso = fetchIpfs {
    cid = "QmRnfjQv7ajfJjYhwRGqahsmhcCKMFhuicoLAqB4AiAG77";
    fallbackUrl = "https://archive.org/download/acpp_20251225/ACPP.iso";
    hash = "sha256-4zv+7AG7mKVyD9U2A8+IcmsqXBKdizQWBjAliuwP3cA=";
    name = "alpha-centauri-planetary-pack-acpp.iso";
  };

  # Yitzi's Unofficial SMAX Patch 3.5: a complete unprotected terranx.exe
  # (3076096 B) built on the official SMACX v2.0 patch plus Kyrub's and
  # Scient's fixes, shipped with the text files it requires (alphax, helpx,
  # script, labels). Its import table is system DLLs only (ADVAPI32, DDRAW,
  # DPLAYX, DSOUND, GDI32, KeRNeL32, MSVFW32, SHELL32, USER32, WINMM,
  # comdlg32) -- no prax.dll import, so the bundled PRACX renderer is optional
  # and deliberately NOT installed: it would replace the renderer, and the
  # DirectDraw=0 path documented below already draws natively at 1920x1080.
  #
  # This is the one deviation from shipping a tree as its vendor built it: the
  # binary carries patch 3.5's community bug and AI fixes. It is the only
  # anonymously obtainable unprotected SMACX executable that exists -- the
  # official patches are no longer hosted anywhere reachable
  # (alphacentauri2.info/official/... 404s, koti.mbnet.fi is long gone).
  patch = fetchIpfs {
    cid = "QmTSowk4VUSA5gFfMd3hEGeeCWBSidkvqV9XSBPAnxW5A7";
    fallbackUrl = "https://archive.org/download/yitzis-unofficial-smax-patch-3.5-3.5d/Yitzi%27s%20Unofficial%20SMAX%20patch%203.5.zip";
    hash = "sha256-+pN93hN5804SPxe/s7t3Q6/WEATBoNpfOKZp/Ems9eo=";
    name = "yitzis-unofficial-smax-patch-3.5.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sid-meyers-alpha-centauri";

  src = iso;

  ipfsSources = [
    iso
    patch
  ];

  nativeBuildInputs = [
    p7zip
    unzip
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/iso"
    7z x -y -o"$TMPDIR/iso" "$src" >/dev/null

    # What the disc's own installer does: programs/ IS the install tree, and
    # the media directories sit beside it at the disc root.
    cp -r "$TMPDIR/iso/programs"/. "$out"/
    cp -r "$TMPDIR/iso/movies" "$TMPDIR/iso/voices" "$TMPDIR/iso/fx" "$out"/
    chmod -R u+w "$out"

    # SafeDisc, its loader stubs, and the EA registration / DirectPlay
    # redistributables: unusable under Proton and read by nothing here.
    rm -f "$out/terran.exe" "$out/terranx.exe" \
          "$out/Terran.icd" "$out/Terranx.icd" \
          "$out/clokspl.exe" "$out/clcd16.dll" "$out/clcd32.dll" \
          "$out/drvmgt.dll" "$out/dplayerx.dll" "$out/secdrv.sys" \
          "$out/Ip.exe" "$out/ip.cfg" \
          "$out"/*.url

    # Unprotected terranx.exe plus the text files patch 3.5 requires. The
    # download nests a second zip inside the first.
    unzip -q ${patch} -d "$TMPDIR/patch"
    unzip -q "$TMPDIR/patch/Alpha Centauri Patch.zip" -d "$TMPDIR/patchfiles"
    for f in terranx.exe alphax.txt helpx.txt script.txt labels.txt; do
      install -m0644 "$TMPDIR/patchfiles/$f" "$out/$f"
    done

    # The disc-root marker, kept so the virtual CD-ROM drive wired up in
    # preRun looks like the real disc to the engine's jackal CD check.
    install -m0644 "$TMPDIR/iso/DATA.TAG" "$out/DATA.TAG"

    # Drop the shipped Alpha Centauri.Ini so preRun can seed a fresh one
    # into the overlay upper on first launch instead of copying up a
    # read-only nix-store file.
    rm -f "$out/Alpha Centauri.Ini"
  '';

  runtime = "proton";

  # DO NOT re-add a DirectDraw COM CLSID registration here. An earlier
  # revision of this file registered CLSID
  # {d8f1eee0-f634-11cf-8700-00a0245d918b} and TreatAs-mapped it to
  # CLSID_DirectDraw, believing terranx created DirectDraw over COM. That
  # GUID is not DirectDraw at all -- it is Aureal A3D (Audio3D_CLSID), and
  # the CoCreateInstance comes from soundx.dll (Miles Sound System), not
  # from terranx: the GUID bytes appear only in sound.dll/soundx.dll, and
  # terranx's import table lists DirectDrawCreate + DirectDrawEnumerateA as
  # static DDRAW.dll imports with no ole32 import at all. The registration
  # therefore handed Miles an IDirectDraw and it called A3D vtable slots on
  # it, which is what produced the "crash inside Wine's ddraw.dll"
  # (ddraw+0x2476d) that the crash was then blamed on. The A3D probe
  # failing ("com_get_class_object ... not registered") is normal on any
  # non-Aureal machine and is harmless.
  #
  # The real crash was ours: terranx+0x245963 `rep movsl` with EDI=0, i.e.
  # memcpy(NULL, palette, 256). The NULL came from
  # CreateFileW("territory.tmp", GENERIC_READ|GENERIC_WRITE, CREATE_ALWAYS)
  # returning status c00000d4 = STATUS_NOT_SAME_DEVICE (EXDEV) -- the
  # overlay copy-up bug fixed in mk-game.nix by "fix overlay copy-up EXDEV
  # (games can't write next to binary)". SMAC regenerates ~40 palette-derived
  # scratch files (territory/bluetint/colorvals/fade/palcheck/reddish/
  # redtint/shadow/spotlight/bodygrads/armorgrads/explosions*.tmp) next to
  # its binary with CREATE_ALWAYS, so it needs a working copy-up. Nothing
  # game-specific is required; the fix was rebasing onto that commit.
  #
  # DirectDraw=0 is a resolution choice, NOT a workaround: it skips SMAC's
  # own fullscreen modeswitch and renders at the surface resolution, so the
  # engine draws natively at gamescope's 1920x1080 and gets a sharp UI plus
  # much more visible map. DirectDraw=1 also works (verified headless on
  # GE-Proton11-1: it modeswitches to 1024x768 and gamescope
  # pillarboxes/upscales it) -- the older claim that it "exits within ~1s
  # without ever opening a window" was the EXDEV crash, not a modeswitch
  # failure. Proton is not pinned (see AGENTS.md), so re-check after a bump.
  #
  # ds3d/eax=0 keep the Miles wrapper on plain DirectSound. This is the
  # vendor's own troubleshooting advice (readme.txt item 11: "If you're
  # experiencing crashes in the sound.dll ... try setting the EAX and DS3D
  # entries to 0") kept as a precaution.
  #
  # Seeded write-if-absent, not rewritten per launch: SMAC owns this file at
  # runtime and rewrites it on exit with the player's preferences (
  # Difficulty, Faction, Preferences bitmaps, Latest Save, ...) while
  # faithfully round-tripping the keys above. Overwriting it every launch
  # would silently reset the player's settings. The file lives in the
  # per-game fuse-overlayfs upper, which survives a wineprefix wipe.
  preRun = ''
    if [ ! -f "$STROM_OVERLAY/Alpha Centauri.Ini" ]; then
      cat > "$STROM_OVERLAY/Alpha Centauri.Ini" <<'EOF'
    [Alpha Centauri]
    DirectDraw=0
    ds3d=0
    eax=0
    [PREFERENCES]
    ForceOldVoxelAlgorithm=1
    EOF
    fi

    # Make d: a fake CD-ROM of the game data so the engine's jackal CD check
    # is satisfied. terranx.exe imports GetDriveTypeA + FindFirstFileA and,
    # finding no DRIVE_CDROM, opens the jackal.txt dialog "The Alpha Centauri
    # CD-ROM was not detected. Some game features will not function without
    # the CD in the drive unless you have performed a 'Complete Install'."
    # every launch (measured headless: the dialog is the first frame, and it
    # is only a warning, but it blocks an unattended start). A plain
    # dosdevices symlink registers as DRIVE_FIXED; wine's mountmgr
    # create_drive_devices() takes the type from HKLM\Software\Wine\Drives,
    # where "cdrom" -> DRIVE_CDROM, which is what winecfg writes for a CD-ROM
    # drive. $GAMEDIR is the merged overlay and holds the whole disc tree
    # (movies/, voices/, fx/, the .txt data files and DATA.TAG), so whatever
    # the check probes for is there. Same convention as
    # games/lands-of-lore-ii-guardians-of-destiny.
    #
    # mountmgr reads the value at wineserver init, so on a brand-new prefix
    # the drive type lands on the SECOND launch (the same ordering as
    # games/gothic and games/sid-meier-s-civilization-iii); the first launch
    # still shows the dialog once.
    pfx="$STROM_COMPATDATA/0/pfx"
    mkdir -p "$pfx/dosdevices"
    ln -snf "$GAMEDIR" "$pfx/dosdevices/d:"
    # d:: is wine's unix-device link. A directory-backed virtual CD has no
    # /dev/srN node, so point it at the same dir to keep the drive well-formed
    # without claiming a real device.
    ln -snf "$GAMEDIR" "$pfx/dosdevices/d::"

    SYSREG="$pfx/system.reg"
    if [ -f "$SYSREG" ] && ! grep -qF '[Software\\Wine\\Drives]' "$SYSREG"; then
      {
        printf '\n[Software\\\\Wine\\\\Drives] %s\n' "$(date +%s)"
        printf '"d:"="cdrom"\n'
      } >> "$SYSREG"
    fi
  '';

  # Verified empirically: after reaching an in-game map and letting the
  # engine autosave, drive_c/users/steamuser/ contained nothing but Wine's
  # own skeleton directories (no vendor or game dir anywhere under
  # AppData/{Roaming,Local,LocalLow} or Documents), while
  # "saves/auto/Alpha Centauri Autosave 1.SAV" (287408 bytes) and the
  # rewritten Alpha Centauri.Ini appeared next to the binary in the
  # per-game fuse-overlayfs upper. SMAC keeps everything in its install
  # dir, so there is nothing under the wineprefix to relocate.
  saveLocations = [ ];
  # terranx.exe is the Alien Crossfire (SMACX) expansion executable, the
  # superset that the Planetary Pack is built around.
  executable = "terranx.exe";

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
    description = "Sid Meier's Alpha Centauri - Planetary Pack (Firaxis 1999, Alien Crossfire from the retail disc + unofficial SMAX patch 3.5, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sid-meyers-alpha-centauri";
  };
}
