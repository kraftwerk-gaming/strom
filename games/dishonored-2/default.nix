{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

let
  # Dishonored 2 (Arkane Studios / Bethesda 2016) - void-engine immersive
  # sim, 64-bit, D3D11. Denuvo was stripped from the retail build by
  # Bethesda post-launch, so shipping builds are DRM-free.
  #
  # SOURCE: the GOG release, as a pre-installed tree. archive.org item
  # `dishonored-2_202607` holds one 42,343,019,616-byte `Dishonored 2.zip`
  # (sha1 4a7b0618d8a49ca60c22045b5d09b2386e9e53c2 per the item metadata),
  # a ZIP64 archive of 224 entries rooted at `Dishonored 2/`:
  # Dishonored2.exe next to base/ (the void engine's .resources/.index
  # data packs, pck/ Wwise banks, video/ Bink cutscenes and a prebaked
  # base/shaderCache/) plus the bundled DLLs. No installer pass is needed,
  # so a plain unzip at build time yields a ready-to-run tree.
  #
  # PROVENANCE / why this is not the tree the first staging attempt used.
  # That attempt packaged the AnkerGames pre-installed CODEX release
  # (`dishonored-2.rar`, expected sha256-dRWth6194Tk/tbgRjRU4x8Mds15Mp7Ctvk3LqNXstW4=)
  # and got as far as the title screen. Its bytes were never IPFS-pinned
  # (`cid` stayed PENDING_UPLOAD), the local store path was later
  # garbage-collected, and ankergames.net is Cloudflare-fronted, so a
  # headless session cannot re-fetch it: the curl fallback silently saves
  # the 418 KB challenge page in place of the archive. The hash above is
  # kept only so that tree stays identifiable if it ever resurfaces.
  #
  # STEAMWORKS / GALAXY. The CODEX tree needed a Steamworks emulator
  # (its bundled emu returned null interface pointers offline and the
  # engine access-violated during Steamworks init), which is why that
  # attempt swapped in gbe_fork's steam_api64.dll. This tree needs no
  # emulator and carries no steam_api64.dll at all. Import tables, read
  # off the actual PE files:
  #
  #   Dishonored2.exe  -> ..., common.dll, d3d11.dll, dxgi.dll, d3d9.dll,
  #                       bink2w64.dll, amd_ags_x64.dll, AnselSDK64.dll,
  #                       GFSDK_SSAO_D3D11.win64.dll, DINPUT8.dll,
  #                       XINPUT9_1_0.dll, WINHTTP/WS2_32/WSOCK32/...
  #                       (24 static, 0 delay-loaded)
  #   common.dll       -> Galaxy64.dll (11 symbols: galaxy::api::Init,
  #                       Shutdown, ProcessData, User, Friends, Stats,
  #                       Apps, Matchmaking, Networking, and the two
  #                       ListenerRegistrar accessors)
  #
  # common.dll is GOG's Steamworks-to-Galaxy bridge: it exports the
  # steam_api surface the engine still calls (Init, Shutdown,
  # CreateInterface, GetHUser, GetHPipe, Register/UnregisterCallback,
  # RunCallbacks, Register/UnregisterCallResult) and implements it
  # against Galaxy. So the Steamworks entry point here is common.dll, not
  # steam_api64.dll, and a gbe_fork drop-in would have nothing to replace.
  # galaxy::api::Init does sit on the startup path via that chain, but it
  # succeeds without a Galaxy client and the game plays offline (verified
  # by running it, not assumed - see the commit message).
  src = fetchIpfs {
    cid = "QmdDLjNHvTZgjLkkZaQURFGoWpvTrm9MFjxUBLi66AnHev";
    fallbackUrl = "https://archive.org/download/dishonored-2_202607/Dishonored%202.zip";
    hash = "sha256-rTyudw2iRRAxx+f6b4B16vPf1pwdr+NpuruDq9Lqvl0=";
    name = "dishonored-2-gog.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "dishonored-2";

  inherit src;

  ipfsSources = [ src ];

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out"
    unzip -q "$src" -d "$out"

    # Flatten the `Dishonored 2/` wrapper so Dishonored2.exe lands at
    # $out/Dishonored2.exe. These are renames within $out, not a second
    # 48 GB copy.
    find "$out/Dishonored 2" -mindepth 1 -maxdepth 1 -exec mv -t "$out" {} +
    rmdir "$out/Dishonored 2"
    chmod -R u+w "$out"

    # GOG installer leftovers: the Inno uninstaller (an .exe nothing here
    # should ever run), the desktop shortcut, the Galaxy store webcache
    # and the installer icons. The goggame-1431426311.* manifests and
    # goglog.ini stay - they are what Galaxy64.dll reads, they total a
    # couple hundred KB, and goglog.ini is the SDK's log config.
    rm -f "$out/unins000.dat" "$out/unins000.exe" "$out/unins000.ini" \
      "$out/unins000.msg" "$out/Dishonored2 - Shortcut.lnk" \
      "$out/webcache.zip" "$out/gog.ico" "$out/support.ico"
  '';

  runtime = "proton";
  executable = "Dishonored2.exe";

  # Dishonored 2 keeps savegames, the profile and the settings .cfg under
  # C:\Users\<user>\Saved Games\Arkane Studios\Dishonored2\. GOG's own
  # goggame-1431426311.script declares the same path
  # ("savePath": "{userdocs}/../Saved Games/Arkane Studios/Dishonored2",
  # plus base/savegame/profile.bin), and a run of this package confirms
  # the engine creates exactly that tree and nothing else outside
  # AppData/Local/Microsoft. Relocate the Arkane Studios parent so
  # progress survives wineprefix wipes.
  saveLocations = [ "Saved Games/Arkane Studios" ];

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
    description = "Dishonored 2 (Arkane Studios 2016, GOG pre-installed tree, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "dishonored-2";
  };
}
