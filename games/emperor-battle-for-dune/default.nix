{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  cabextract,
  unar,
}:

let

  # wheybags' patched repack: official 1.09 retail + EmperorLauncher
  # (https://wheybags.com/blog/emperor.html) — restored multiplayer,
  # HD-resolution patch, modernised network code. Self-extracting RAR
  # SFX. Top-level layout after extraction:
  #   Emperor battle for dune - patched/
  #     EmperorLauncher.exe   <- launches data/Game.exe with -w hook
  #     EmperorHooks.dll
  #     data/                 <- pre-installed game files (EMPEROR.EXE,
  #                              Game.exe, DATA/, disks/, WOL/, ...)
  #
  # The shipped EmperorLauncher.exe is a community re-patched build of
  # wheybags' v1.0 source with the Game.exe md5 check inverted (two
  # bytes at 0x365D / 0x36AD), so the launcher's "Install to <dir>?"
  # CD prompt is skipped — the repack ships an already-installed data
  # tree with Game.exe md5 d31074c8c393bc08ab9f144f767bbaa8, which
  # doesn't match wheybags' expected post-RTPatch hash but is fully
  # playable when the launcher's UI is the entry point.
  gameSrc = fetchIpfs {
    cid = "QmVuVwSfwjHY7aKCWePoQSPnBzqZRt3SLXwExR3Ps5SHB3";
    fallbackUrl = "https://archive.org/download/emperor-battle-for-dune-patched/Emperor%20battle%20for%20dune%20-%20patched.exe";
    hash = "sha256-xOT9cqpoqNZFu+LG6BKrJE6Y+PtLcdkaY+T0wdwN+QU=";
    name = "emperor-battle-for-dune-patched.exe";
  };

  # Microsoft VB6 SP6 OLEAUT32 Security Update (KB946235, Dec 2007).
  # 1.5 MB self-extracting cabinet that contains pre-Win7 patched
  # OLEAUT32.DLL variants — including oavisrtm.dll, the Vista-RTM
  # build that exports ordinal 444 (OaEnablePerUserTLibRegistration).
  # EmperorLauncher.exe imports OLEAUT32 by ordinal 444; wine's builtin
  # OLEAUT32 (through wine 11.9) stops at ordinal 443, so clicking
  # "Play" in the launcher crashes the in-process Detours-injected
  # Game.exe child with:
  #   wine: Call from ... to unimplemented function OLEAUT32.dll.444
  # Reported across wheybags/EmperorLauncher#4, #7, #15. The standard
  # fix is winetricks oleaut32 (winetricks's win7sp1-sourced DLL),
  # but that bake pulls a 537 MB KB. oavisrtm.dll from KB946235 is
  # a tenth the size and still provides ordinal 444.
  vb6OleautKB = fetchurl {
    url = "https://download.microsoft.com/download/8/c/a/8cada3d5-e737-4a5d-8c27-e1fbc4c32be7/VB6-KB946235-x86-ENU.exe";
    hash = "sha256-eiQR4lw6Fa2OqucQNiNmsMsdvIZsxs3K+0EA8YCEIog=";
    name = "VB6-KB946235-x86-ENU.exe";
  };

in
self.lib.mkGame { inherit lib pkgs; } {
  name = "emperor-battle-for-dune";

  src = gameSrc;

  nativeBuildInputs = [
    unar
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out"

    # RAR SFX; unar drops a single top-level dir "Emperor battle for dune - patched"
    unar -f -o /tmp/ebfd ${gameSrc}
    cp -r "/tmp/ebfd/Emperor battle for dune - patched/"* "$out/"
    rm -rf /tmp/ebfd

    # Stage Vista's oleaut32.dll (oavisrtm.dll inside the KB cabinet)
    # next to the launcher so preRun can drop it into the wineprefix.
    # See top-level comment on vb6OleautKB.
    cabextract -L -d "$TMPDIR/oleaut" -F 'oavisrtm.dll' ${vb6OleautKB}
    install -m0644 "$TMPDIR/oleaut/oavisrtm.dll" "$out/oleaut32-vista.dll"

    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # Engine writes saves to data\saves (resource.cfg: SAVED_GAMES =
  # data\saves). That path lives inside the install dir, so saves
  # persist through the per-game fuse-overlayfs upper — no $HOME
  # relocation needed.
  saveLocations = [ ];

  # EmperorLauncher.exe is the wheybags front-end: it presents a small
  # window with two radio buttons ("Host game / singleplayer" — the
  # default — and "Connect to server"), a few debug checkboxes, and a
  # "Play" button. Clicking Play uses Microsoft Detours to
  # DetourCreateProcessWithDllA(Game.exe -w, EmperorHooks.dll) — i.e.
  # spawns the actual game binary with the hooks DLL injected for
  # windowed mode + HD-resolution + multiplayer support.
  #
  # The dialog can read as a "multiplayer-only" UI at first glance
  # because the right half is dominated by server-IP / Test-connection
  # widgets, but the LEFT radio "Host game / singleplayer" is the
  # singleplayer-campaign entry point — leave it selected and click
  # Play to start the Dune campaign.
  executable = "EmperorLauncher.exe";

  env = {
    # WINEDLLOVERRIDES=oleaut32=n,b: prefer the native (Vista) DLL we
    # drop into syswow64 over wine's builtin. Without this, even with
    # the file present, wine will keep loading its own builtin and
    # ordinal 444 will stay unimplemented (see vb6OleautKB note).
    WINEDLLOVERRIDES = "oleaut32=n,b";

    # DXVK can mis-handle writes to LDR_DATA_TABLE_ENTRY pages that
    # Detours' inline hooks mutate; STAGING_WRITECOPY ensures
    # copy-on-write semantics survive the Detours rewrite.
    STAGING_WRITECOPY = "1";
  };

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--force-grab-cursor" = true;
      "--expose-wayland" = true;
    };
  };

  # TODO(stage): runtime testing pending. Westwood SafeDisc-era titles
  # often need PROTON_USE_WINED3D=1 because DXVK trips on the d3d8
  # immediate-mode + bink movie path; the wheybags HD-patch hooks
  # ddraw/d3d8 directly so this may or may not still apply. Try
  # default proton first; if Game.exe black-screens or crashes on
  # movie playback, add:
  #   PROTON_USE_WINED3D = "1";
  # to env and possibly WINEDLLOVERRIDES = "ddraw=n,b" to force the
  # wheybags ddraw shim over wine's builtin.
  preRun = ''
    export LD_LIBRARY_PATH="/usr/lib32''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # Drop the native (Vista RTM) oleaut32.dll into the prefix's
    # syswow64 so the WINEDLLOVERRIDES=oleaut32=n,b above resolves to
    # a real native DLL. Without this the launcher's "Play" button
    # crashes with `Call to unimplemented function OLEAUT32.dll.444`
    # (the export Detours requires is OaEnablePerUserTLibRegistration,
    # ordinal 444 — present in Vista's oleaut32 but absent from wine
    # builtin through 11.9). Sentinel-gated so we don't re-copy on
    # every launch.
    PFX="$STROM_COMPATDATA/0/pfx"
    SYSWOW64="$PFX/drive_c/windows/syswow64"
    OLE_SENTINEL="$PFX/.strom-oleaut32-vista-installed"
    if [ -d "$SYSWOW64" ] \
        && [ -f "$STROM_OVERLAY/oleaut32-vista.dll" ] \
        && [ ! -e "$OLE_SENTINEL" ]; then
      if [ -e "$SYSWOW64/oleaut32.dll" ] || [ -L "$SYSWOW64/oleaut32.dll" ]; then
        mv -f "$SYSWOW64/oleaut32.dll" "$SYSWOW64/oleaut32.dll.builtin" \
          2>/dev/null || true
      fi
      install -m0644 "$STROM_OVERLAY/oleaut32-vista.dll" \
        "$SYSWOW64/oleaut32.dll"
      touch "$OLE_SENTINEL"
    fi
  '';

  meta = {
    description = "Emperor: Battle for Dune (Westwood 2001, via Proton with wheybags HD/multiplayer patch)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "emperor-battle-for-dune";
  };
}
