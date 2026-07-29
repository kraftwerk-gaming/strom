{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
}:

let
  # Sid Meier's Civilization III Complete (Firaxis 2001), GOG re-release
  # v2.0.0.7 (base Civilization III + Play the World + Conquests),
  # distributed as a single GOG Inno Setup installer .exe. innoextract --gog
  # puts the whole game tree under app/, with the Conquests expansion under
  # app/Conquests/ (Civ3Conquests.exe is the default-launched Complete binary).
  #
  # The engine is 2D: jgl.dll ("Jackal graphics system", loaded by name at
  # runtime) rasterizes into a GDI DIB section and BitBlt/StretchBlt's it to the
  # window. Civ3Conquests.exe's only OPENGL32 imports are the fixed-pipeline
  # line calls (glBegin/glVertex2i/glOrtho/glLineStipple) used for the map
  # gridlines overlay; there is no ddraw/d3d import at all. Nothing here needs a
  # GL profile override or a colour-depth mode-set.
  #
  # DIAGNOSTIC NOTE FOR WHOEVER TOUCHES THIS NEXT: in this engine a missing
  # asset presents as a BLACK SCREEN, not as an error. When a lookup fails the
  # engine tries to raise one of its jackal.txt dialogs (INSTALLATION_ERROR_CIV3
  # etc.). That popup's initialiser copies the global default-font pointer
  # (.data 0xcadf78) into its ~9.9 KB stack object at +0x2044, and the layout
  # pass at civ3conquests+0x212dd8 dereferences it unconditionally
  # ("mov edx,[ecx+0x10]", the load is hoisted above its guarding branch). Early
  # in startup that global is still NULL, so the dialog access-violates before
  # it can draw; the game's own SEH swallows the fault and it limps on in its
  # message loop presenting an unpainted window. Every black screen this package
  # ever showed was that: a data-path bug wearing a rendering bug's clothes.
  # Diagnose with WINEDEBUG=+file and look for the last failed lookup, not with
  # GL debugging.
  src = fetchIpfs {
    cid = "QmUFHAMKWQVg67WmQLTHiMyX2DJw1WUYuVaAEiFRjfVyjN";
    fallbackUrl = "https://archive.org/download/civ3windowsbuilds/Sid%20Meier%27s%20Civilization%20III%20Complete%20%5BGOG%5D/setup_civilization3_complete_2.0.0.7.exe";
    hash = "sha256-StVMowjqk69JsNs6eVc27aka7WHIzXOxgZaALQ9NI5U=";
    name = "setup_civilization3_complete_2.0.0.7.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "sid-meier-s-civilization-iii";

  inherit src;

  nativeBuildInputs = [
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    innoextract --gog -d "$TMPDIR/iss" "$src"
    # The GOG installer nests the game tree under app/; promote it to $out.
    cp -r "$TMPDIR/iss/app"/. "$out"/

    # GOG parks five files the game needs under __support/save/, in a tree that
    # mirrors the install root exactly, and has its installer copy them into
    # place as a post-install step (that is what __support/save is for -- it is
    # also what GOG restores over a reinstall so a player's tweaks survive).
    # An extract-only build has to do that copy itself. `innoextract --gog -l`
    # on setup_civilization3_complete_2.0.0.7.exe lists exactly:
    #     app/__support/save/LSANS.TTF                 (58.1 KiB)
    #     app/__support/save/civ3PTW/LSANS.TTF         (58.1 KiB)
    #     app/__support/save/Conquests/LSANS.TTF       (58.1 KiB)
    #     app/__support/save/Conquests/conquests.biq   (29.8 KiB)
    #     app/__support/save/Conquests/conquests.mb    (4 B)
    # LSANS.TTF is the Lucida Sans face the Jackal UI rebuilds LSANS.fot from;
    # conquests.biq + conquests.mb are the Conquests default ruleset and its
    # label index, the counterparts of the vanilla civ3mod.bic + civ3id.mb and
    # of civ3PTW/civ3X.bix + civ3Xid.mb. Without them the engine cannot start
    # any game at all. This promotion MUST happen before __support is deleted;
    # deleting it first (as this recipe used to) is what made the package look
    # like it was missing files the installer does not ship.
    if [ -d "$out/__support/save" ]; then
      cp -r "$out/__support/save"/. "$out"/
    else
      echo "expected __support/save in the GOG payload, layout changed" >&2
      exit 1
    fi

    # GOG installer debris + GOG Galaxy support: not needed at runtime.
    rm -rf "$out/Redist" "$out/__support" "$out/tmp"
    rm -f "$out/goggame-"*.info "$out/goggame-"*.hashdb \
          "$out/goggame-"*.dll "$out/goggame-"*.ico \
          "$out/Conquests/goggame-"*.dll \
          "$out/galaxy_"*.exe \
          "$out/autorun.exe" "$out/autorun.inf"

    # The engine chmods and deletes Conquests/LSANS.fot on every start and
    # regenerates it from Conquests/LSANS.TTF, so both must be writable in the
    # per-game overlay upper rather than read-only in the store lower.
    chmod 0644 "$out/Conquests/LSANS.fot" "$out/Conquests/LSANS.TTF"
  '';

  runtime = "proton";

  # Civ III Conquests writes everything mutable next to its binary -- confirmed
  # in the overlay upper after a headless playthrough: Conquests/Saves/Auto/
  # "Conquests Autosave 4000 BC.SAV", the copied-up conquests.biq/conquests.mb,
  # the regenerated LSANS.fot and bic__out.tmp. Nothing lands under
  # drive_c/users/steamuser, so the per-game fuse-overlayfs upper is the whole
  # save story and a wineprefix wipe cannot take progress with it.
  saveLocations = [ ];
  executable = "Conquests/Civ3Conquests.exe";

  # Civ3Conquests.exe must run with its CWD inside Conquests/, not at the
  # Complete install root. It resolves ".\CampaignRecord.hof",
  # ".\conquests.ini", ".\conquests.biq", "jackal.txt", "Text\labels.txt" and
  # "Art\..." CWD-relative first, and only then falls back through the two HKLM
  # Install_Path keys seeded in preRun. Started from the root it opened
  # Z:\...\CampaignRecord.hof (STATUS_OBJECT_NAME_NOT_FOUND, c0000034) and
  # loaded the VANILLA Text\labels.txt (17307 bytes) instead of
  # Conquests\Text\labels.txt (27017 bytes) -- both confirmed in a WINEDEBUG
  # +file trace -- and then went black per the diagnostic note above.
  preRun = ''
    cd "$GAMEDIR/Conquests"

    # Registry seeding. The Conquests engine resolves every asset through three
    # tiers, in this order (observed in a WINEDEBUG +file trace of one lookup):
    #   1. CWD-relative                      -> Conquests/art/...
    #   2. HKLM\SOFTWARE\Infogrames Interactive\Civilization III\Install_Path
    #                                        -> <root>/art/...        (vanilla)
    #   3. HKLM\SOFTWARE\Infogrames\Civ3PTW\Install_Path
    #                                        -> <root>/civ3PTW/art/... (PTW)
    # Both key names are in the binary's strings, next to the "A:\" default and
    # INSTALLATION_ERROR_CIV3. Tier 3 MUST point at the civ3PTW subdirectory,
    # not at the root: the Play-the-World-era interface art the Complete main
    # menu needs (art/interface/x_comboTopbar.pcx, x_comboButtons.pcx,
    # x_cycle button *.pcx, x_pref background.pcx) ships ONLY in
    # civ3PTW/Art/interface/. Point tier 3 at the root as well and
    # x_comboTopbar.pcx is unfindable and the engine goes black (see the header).
    # INSTALLATION_ERROR_CIV3 dialog, and that dialog is what faults at
    # civ3conquests+0x212dd8 (see above), which is how a missing expansion
    # sprite turned into a black screen.
    #
    # Appended as raw Wine registry text (regedit is not on PATH at preRun, and
    # bare wine is banned). Proton creates system.reg while starting the game,
    # i.e. after this hook, so on a brand-new prefix the keys land on the next
    # launch; they then persist for the life of the prefix. The 32-bit exe's
    # HKLM reads redirect to Wow6432Node, so seed both views.
    __sysreg="$STROM_COMPATDATA/0/pfx/system.reg"
    if [ -f "$__sysreg" ] \
        && ! grep -q 'Infogrames Interactive\\\\Civilization III' "$__sysreg"; then
      echo "[strom] first-run setup: seeding Civ3 Install_Path registry"
      __gdwin="Z:''${GAMEDIR//\//\\\\}"
      __ts=$(date +%s)
      for __base in \
        'Software\\Infogrames Interactive\\Civilization III' \
        'Software\\Wow6432Node\\Infogrames Interactive\\Civilization III'; do
        {
          printf '\n[%s] %s\n' "$__base" "$__ts"
          printf '"Install_Path"="%s"\n' "$__gdwin"
          printf '"Min_Install"=dword:00000000\n'
        } >>"$__sysreg"
      done
      for __base in \
        'Software\\Infogrames\\Civ3PTW' \
        'Software\\Wow6432Node\\Infogrames\\Civ3PTW'; do
        {
          printf '\n[%s] %s\n' "$__base" "$__ts"
          printf '"Install_Path"="%s\\\\civ3PTW"\n' "$__gdwin"
          printf '"Min_Install"=dword:00000000\n'
        } >>"$__sysreg"
      done
      unset __gdwin __ts __base
    fi
    unset __sysreg

    # conquests.ini lives next to Civ3Conquests.exe (the engine opens
    # ".\conquests.ini", CWD-relative) under a [Conquests] header. PlayIntro=0
    # skips the Bink intro movie; KeepRes=1 keeps the desktop resolution instead
    # of issuing a ChangeDisplaySettings mode-set that gamescope's nested
    # Xwayland cannot satisfy; Video Mode=1024 asks for the 1024x768 layout,
    # which fits inside the 1920x1080 gamescope surface. Rewritten by staging in
    # the sandbox tmpfs and cat'ing the result over the file: neither sed -i's
    # rename nor unlink of a fresh file inside the fuse-overlayfs upper works
    # (both fail EXDEV), while an in-place cat does. Any other key the game
    # already wrote is preserved.
    __ini="$GAMEDIR/Conquests/conquests.ini"
    __tmp="/tmp/.strom-conquests-ini.$$"
    : > "$__tmp"
    if [ -e "$__ini" ]; then
      grep -viE '^(PlayIntro|KeepRes|Video Mode)=' "$__ini" > "$__tmp"
    fi
    if ! grep -q '^\[Conquests\]' "$__tmp"; then
      printf '%s\n' '[Conquests]' >> "$__tmp"
    fi
    printf '%s\n' 'PlayIntro=0' 'KeepRes=1' 'Video Mode=1024' >> "$__tmp"
    cat "$__tmp" > "$__ini"
    rm -f "$__tmp"
    unset __ini __tmp
  '';

  meta = {
    description = "Sid Meier's Civilization III Complete (Firaxis 2001, GOG v2.0.0.7: base + Play the World + Conquests, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "sid-meier-s-civilization-iii";
  };
}
