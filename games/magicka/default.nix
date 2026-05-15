{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  zstd,
}:

let
  # Pioneer / SGi pre-installed Magicka v1.10.4.2 with all DLC. Plain RAR
  # archive of a fully-extracted Steam game folder (NOT a FreeArc/Inno
  # installer): the rar's first level is "Magicka.v1.10.4.2/" containing
  # Magicka.exe, Content/, Cursors/, Dependencies/, plus a bundled
  # Steamworks emulator stub (steam_api.dll + steam_interfaces.txt +
  # steam_appid.txt + account_name.txt) so SteamAPI_Init returns synchronously
  # without needing a real Steam process. This is the same v1.10.4.2 build
  # the FreeArc t1coon repack ships, just delivered as a directly-extractable
  # pre-installed package which sidesteps the unarc.dll/ISDone.dll/XDelta3
  # dance entirely. Distributed via SteamUnlocked's mega.nz mirror.
  src = fetchIpfs {
    cid = "QmYjA47DUhTPt6aTMcjBHPtr1a1Mk2LXLYv6orJ6hNT2Gy";
    fallbackUrl = "https://steamunlocked.one/magicka-free-download/";
    hash = "sha256-ycDulLu4WnkxIfUbP7LJ9Y6lLKXmtLGvQYGmtP549d4=";
    name = "magicka.rar";
  };

  # Pre-baked wineprefix tarball. Magicka.exe is mixed-mode C++/CLI built
  # against XNA 3.1, whose Microsoft.Xna.Framework.dll carries native code
  # that wine-mono 10.4.1's JIT cannot translate (mscoree returns a real
  # but useless GraphicsDevice; GraphicsDevice.CreationParameters returns
  # null and every D3D draw call NPEs). The standard fix (Proton #458,
  # PCGamingWiki) is real Microsoft .NET 3.5 + XNA 3.1 + Managed DirectX in
  # the prefix. We pre-bake that prefix at build-host time (winetricks
  # `dotnet35sp1 xna31 d3dx9_43` + manual Managed DirectX 1 placement
  # from directx_Jun2010_redist.exe's Apr2006_MDX1_x86.cab) and ship it
  # as a tarball so end users never run winetricks.
  #
  # Extraction: preRun unpacks into $STROM_COMPATDATA/0/ on first launch
  # (sentinel: $STROM_COMPATDATA/0/.magicka-prefix-installed). proton's
  # autoWipePrefix is disabled because a wipe would destroy the bake;
  # preRun has its own stale-symlink check that re-extracts on detection.
  prefixTarball = fetchIpfs {
    cid = "Qmbytir26JNwT6dRxvZh8hwFMjGXhg3MUugcbHhtju7KRR";
    hash = "sha256-ablJR6Dw/AO87Wf82lprJv1YSDKmheyMnZ7IvBM/Y9E=";
    name = "magicka-prefix.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "magicka";

  ipfsSources = [
    src
    prefixTarball
  ];

  inherit src;

  nativeBuildInputs = [
    unar
  ];

  # Layout: Magicka.v1.10.4.2/{Magicka.exe, Content/, Cursors/,
  # Dependencies/, steam_api.dll, steam_appid.txt, steam_interfaces.txt,
  # account_name.txt, ...}. Strip the top-level dir so $out/Magicka.exe
  # sits at the root. Drop installer-leftover batch files and the empty
  # Dependencies/ dir. XNA/DirectX/.NET come from the pre-baked prefix
  # (prefixTarball above), not from per-game DLLs next to Magicka.exe —
  # the real Microsoft .NET 3.5 CLR loads them from the GAC, which is
  # what makes XNA 3.1's C++/CLI binaries work.
  buildScript = ''
    mkdir -p "$TMPDIR/extract"
    unar -q -o "$TMPDIR/extract" "$src"
    mkdir -p "$out"
    cp -r "$TMPDIR/extract/Magicka.v1.10.4.2/." "$out/"
    chmod -R u+w "$out"
    rm -f "$out/setup5.bat" "$out/Nickchange.bat" "$out/Uninstall1.bat"
    rm -rf "$out/Dependencies"
    # Pioneer's account_name.txt ships with a non-ASCII trailing space
    # ("SGi "); replace with a clean default. Magicka uses this as the
    # in-game player name when the bundled emu hands a fake Steam account.
    echo -n Wizard > "$out/account_name.txt"

    # The bundled steam_api.dll is Goldberg Steam Emulator (PE32 i386,
    # `Goldberg SteamEmu` signature in .rdata, STEAMAPPS_INTERFACE_VERSION005).
    # `SteamApps::GetCurrentGameLanguage()` reads `language.txt` from
    # one of three places, in upstream Goldberg precedence order:
    #   1. <gamedir>/language.txt          (root, alongside steam_api.dll)
    #   2. <gamedir>/steam_settings/language.txt
    #   3. <gamedir>/settings/language.txt
    # falling back to the hardcoded string `english` if all three are missing.
    # Pioneer's repack placed `account_name.txt` at the gamedir root (not in
    # a subdir), confirming root is where the emu reads from. We drop the
    # file at all three locations to be defensive against fork-specific
    # precedence quirks. Without this, the emu's compiled-in fallback can
    # be overridden by stale per-account `settings/<user_steam_id>/...`
    # state Goldberg writes back, which is how a "russian" string ends up
    # being returned by `GetCurrentGameLanguage()` on subsequent runs.
    echo -n english > "$out/language.txt"
    mkdir -p "$out/steam_settings"
    echo -n english > "$out/steam_settings/language.txt"
    echo -n english > "$out/settings/language.txt"

    # PdxConnect.dll is Paradox Connect's native client. It probes for
    # .NET 4.0 via mscoree's CorBindToRuntimeEx (the v4 wine-mono shim
    # responds, which surfaces a "this app needs .NET 4.0" dialog inside
    # the prefix because our bake only ships real Microsoft v1.1/v2.0/v3.5
    # — not v4). The Paradox login dialog the DLL provides is dead
    # anyway (the auth servers were sunset years ago), and Magicka.exe
    # gracefully degrades to offline mode when PdxConnect's exports return
    # null/E_FAIL, so dropping the DLL eliminates the .NET 4 probe without
    # losing functionality.
    rm -f "$out/PdxConnect.dll"

    # Pioneer/SGi's repack is a Russian localization: when Magicka.exe
    # cannot resolve the Steam-emu language string to a Content/Languages
    # subdir, it falls back to the first directory it finds alphabetically
    # (which would be `deu` on a fresh install with all DLC). The repack
    # also ships a registry-free Russian default baked into the binary's
    # CultureInfo fallback. Strip every non-English Content/Languages
    # subdir so the LanguageManager has only `eng` to choose from; this is
    # the same approach Magicka's official "English-only" repack uses.
    for __lang_dir in deu fra hun ita pol rus spa; do
      rm -rf "$out/Content/Languages/$__lang_dir"
    done

    # Magicka was built against .NET 3.5; supportedRuntime pins the CLR
    # version so the real Microsoft mscoree (installed into the prefix
    # by the bake) picks the v2.0/v3.5 GAC layer where XNA 3.1 lives.
    cat > "$out/Magicka.exe.config" <<'EOF'
    <?xml version="1.0" encoding="utf-8" ?>
    <configuration>
      <startup useLegacyV2RuntimeActivationPolicy="true">
        <supportedRuntime version="v2.0.50727" />
      </startup>
      <runtime>
        <enforceFIPSPolicy enabled="false" />
      </runtime>
    </configuration>
    EOF
  '';

  runtime = "proton";
  executable = "Magicka.exe";

  # zstd needed at runtime by preRun's tarball extraction.
  targetPkgs = p: [ p.zstd ];

  # Pre-baked-prefix gate. The wineprefix (real Microsoft .NET 3.5 +
  # XNA 3.1 GAC + Managed DirectX 1) is ~1.2 GiB unpacked; we lay it
  # down on first run and skip on subsequent runs via the sentinel.
  # Also handles the stale-symlink case ourselves (autoWipePrefix is
  # disabled below so the proton wrapper's auto-wipe doesn't destroy
  # the bake before Magicka runs).
  preRun = ''
    __magicka_sentinel="$STROM_COMPATDATA/0/.magicka-prefix-installed"
    __magicka_pfx="$STROM_COMPATDATA/0/pfx"
    __magicka_restore=0
    if [ ! -f "$__magicka_sentinel" ]; then
      __magicka_restore=1
    elif [ -d "$__magicka_pfx/drive_c" ] && \
         find "$__magicka_pfx/drive_c" -xtype l -lname '/nix/store/*' \
              -print -quit 2>/dev/null | grep -q .; then
      # Same heuristic as proton's autoWipePrefix: a dangling /nix/store
      # symlink means the proton that bootstrapped this prefix has been
      # GC'd. Re-extract to recover.
      echo "magicka: pre-baked prefix has stale /nix/store symlink; restoring" >&2
      __magicka_restore=1
    fi
    if [ "$__magicka_restore" = 1 ]; then
      mkdir -p "$STROM_COMPATDATA/0"
      find "$STROM_COMPATDATA/0" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      tar --zstd -xf ${prefixTarball} -C "$STROM_COMPATDATA/0"
      touch "$__magicka_sentinel"
    fi
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

  # Pre-baked prefix is self-contained: real Microsoft .NET 3.5 + XNA 3.1
  # GAC + Managed DirectX 1 + d3dx9_43. autoWipePrefix would react to any
  # GC'd /nix/store symlink that lands inside the prefix (e.g. when proton
  # bumps and the symlink-pfx patch's default_pfx links go stale) by
  # wiping $STROM_COMPATDATA — that would destroy the bake. preRun above
  # has its own equivalent staleness check that re-extracts the tarball
  # instead of just deleting, so disabling autoWipePrefix here is safe.
  proton.autoWipePrefix = false;

  env = {
    SteamAppId = "42910";
    SteamGameId = "42910";
    PROTONFIXES_DISABLE = "1";
    DXVK_ASYNC = "1";
    LD_LIBRARY_PATH = "/usr/lib32:/usr/lib:/usr/lib64";
    # The Pioneer pack ships its own Steamworks emu DLLs (steam_api.dll +
    # SteamWrapper.dll). Force native (the bundled stubs) to win over
    # Wine's builtin lsteamclient proxy; Wine's lsteamclient would
    # otherwise re-route Magicka.exe's SteamAPI_Init through a real Steam
    # process which doesn't exist in the sandbox.
    WINEDLLOVERRIDES = "steam_api,SteamWrapper=n,b;lsteamclient=";
    # Proton GE auto-launches xalia.exe (its gamescope accessibility
    # helper from files/share/xalia/) inside the prefix on every game
    # start. xalia.exe.config declares
    # `<supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/>`
    # — our pre-baked prefix ships real Microsoft .NET 3.5 only (no v4),
    # so the prefix's syswow64\mscoree.dll fires its standard "To run
    # this application, you first must install one of the following
    # versions of the .NET Framework: v4.0" MessageBox at startup, and
    # the xalia.exe child keeps the proton process tree alive even after
    # Magicka.exe exits. Set PROTON_USE_XALIA=0 (the upstream env-var
    # override in proton's main script) to skip xalia entirely; the game
    # doesn't use the accessibility layer.
    PROTON_USE_XALIA = "0";
  };

  meta = {
    description = "Magicka (Arrowhead Game Studios 2011, all DLC, via Proton with pre-baked .NET 3.5 + XNA 3.1 prefix)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "magicka";
  };
}
