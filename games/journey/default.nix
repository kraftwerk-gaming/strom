{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  runCommandLocal,
  wineWow64Packages,
  xvfb-run,
}:

let
  wine = wineWow64Packages.stable;

  # Inno Setup installer wrapping FreeArc-compressed Files1.bin/Files2.bin/
  # Files3.bin (~1.1 GiB compressed, ~3.4 GiB extracted). The original
  # Annapurna v1.65 build with the engine's MULTi-language tables intact
  # (only english/spanish/russian wired up in the binary's locale enum,
  # but Strings.xme is unmodified). steam_api64.dll is a Goldberg
  # emulator stub so no real Steam process is required.
  src = fetchIpfs {
    cid = "QmfRhR1An2SPijr8oGZZAJTW2LdkqzBTY3P4oYXPT2vZja";
    fallbackUrl = "https://archive.org/download/journey-t1coon/Journey%20%5BMULTi-ENG-RUS%5D%20%5BR%5D%20%5BTN%5D.zip";
    hash = "sha256-o6/orngxuyN9NvIxw7eCzcZ3a3hXQ0cwwsUiNWLltCU=";
    name = "journey-multi-eng-rus.zip";
  };

  # Extract the zip, then run the Inno+FreeArc installer under Wine to
  # decompress Files*.bin into a flat game directory. Plain p7zip cannot
  # see inside the FreeArc archives, which require unarc.dll/ISDone.dll
  # that only run as Win32 PE. xvfb-run gives the installer a stub
  # display so its silent-mode progress dialog has a window to draw on.
  gameData =
    runCommandLocal "journey-data"
      {
        nativeBuildInputs = [
          unzip
          wine
          xvfb-run
        ];
      }
      ''
        mkdir -p "$TMPDIR/zip"
        unzip -q "${src}" -d "$TMPDIR/zip"
        installer="$TMPDIR/zip/Journey [MULTi-ENG-RUS] [R] [TN]/Journey.exe"
        [ -f "$installer" ] || { echo "installer not found"; exit 1; }

        export WINEPREFIX="$TMPDIR/pfx"
        export WINEDEBUG=-all
        export WINEDLLOVERRIDES="mscoree,mshtml="
        mkdir -p "$WINEPREFIX"
        wineboot --init >/dev/null 2>&1 || true

        # The installer's [Files] section uses an IDP/IDPS unarc.dll that
        # writes via Windows API; running with /VERYSILENT suppresses the
        # finish-page dialog so the process exits when extraction is done.
        xvfb-run -a wine "$installer" \
          /VERYSILENT /SUPPRESSMSGBOXES /NOCANCEL /NOICONS \
          /DIR='C:\j' /LOG="$TMPDIR/install.log"

        gameDir="$WINEPREFIX/drive_c/j"
        [ -f "$gameDir/Journey.exe" ] || {
          echo "extraction failed; install.log:"
          tail -50 "$TMPDIR/install.log" 2>/dev/null || true
          exit 1
        }

        mkdir -p "$out"
        cp -r "$gameDir"/. "$out"/
        # Drop the uninstaller/icons (we run from $out read-only).
        rm -f "$out/unins000.exe" "$out/unins000.dat" \
              "$out/GameIcon.ico" "$out/Uninstall.ico"
      '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "journey";

  ipfsSources = [ src ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/. "$out"/
  '';

  runtime = "proton";
  executable = "Journey.exe";

  saveLocations = [
    "AppData/Local/Annapurna Interactive"
    "Documents/Journey"
  ];
  # Engine cmdline parser maps `-resolution=1080p` to 1920x1080. The
  # Documents/Journey/Journey.cfg <Screen Width Height/> overrides the
  # cmdline once the cfg exists, so we additionally seed that file in
  # preRun (chmod 0444 to lock it).
  executableArgs = [
    "-resolution=1080p"
  ];

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

  env = {
    SteamAppId = "638230";
    SteamGameId = "638230";
    PROTON_NO_GAME_FIXES = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    # Bundled Goldberg steam_api64.dll handles steam stubs; disable
    # Wine's lsteamclient proxy whose Source ABI is incomplete here.
    WINEDLLOVERRIDES = "steam_api64=n,b;lsteamclient=";
  };

  # First-launch fix for the 768x480 lower-left-quadrant render and for
  # the locale fallback: without a Journey.cfg present the engine derives
  # a default 768x480 resolution and writes that to disk on first run,
  # after which the cfg's <Screen Width Height> overrides the cmdline
  # arg forever. Seed a complete Journey.cfg with 1920x1080 +
  # Language=english and chmod 0444 it so the engine's exit-time
  # rewrite (which would clobber the values back to the actual rendered
  # backbuffer size) silently fails.
  preRun = ''
    cfg_dir="$STROM_COMPATDATA/0/pfx/drive_c/users/steamuser/Documents/Journey"
    cfg="$cfg_dir/Journey.cfg"
    mkdir -p "$cfg_dir"
    if [ ! -f "$cfg" ] || [ ! -w "$cfg" ]; then
      install -m 0644 ${./Journey.cfg.template} "$cfg"
    fi
    sed -i \
      -e '/<Screen /{ s|Width="[0-9]*"|Width="1920"|; s|Height="[0-9]*"|Height="1080"|; s|FullScreen="[^"]*"|FullScreen="true"|; }' \
      -e 's|<Language ID="[^"]*"/>|<Language ID="english"/>|' \
      "$cfg"
    chmod 0444 "$cfg"
  '';

  meta = {
    description = "Journey (thatgamecompany 2019, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "journey";
  };
}
