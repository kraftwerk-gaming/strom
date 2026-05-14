{
  self,
  lib,
  pkgs,
  fetchIpfs,
  zstd,
  gnutar,
}:

let
  # Pre-baked Freelancer post-install tree. Produced outside the agent
  # by:
  #   1. Extracting the retail CD CAB1/CAB2 (vanilla DATA/EXE/DLLS).
  #   2. Overlaying FLHDE 0.7.1 — bundles the no-CD patched
  #      Freelancer.exe (the retail GAME/EXE/FREELA_1.EXE is
  #      SafeDisc-2 wrapped and can't load under wine), Jason's
  #      Freelancer Patch, HD textures, FLSharp/FLPlusPlus/FLHook
  #      community fixes, and Win10/11 compat patches.
  #   3. Dropping Proton-GE's DXVK 32-bit d3d8/d3d9 next to
  #      Freelancer.exe so the engine's IDirect3D8 path uses DXVK
  #      instead of wine's wined3d wrapper (which 2003 Freelancer's
  #      video-card detection trips over).
  #   4. Installing the MS Game Studios redistributable into the bake
  #      wineprefix (provides native mfc42.dll/msvcrt/comctl32/etc.
  #      that FLServer.exe imports by name).
  #   5. Folding the entire tree to lowercase (cab1 ships lowercase,
  #      FLHDE ships uppercase — on case-sensitive ext4 the engine's
  #      data lookups would split between both).
  #   6. Writing a `freelancer-seed.reg` at the tree root that
  #      restates HKLM\Software\Microsoft\Microsoft Games\Freelancer\
  #      1.0\{AppPath,DataPath,InstallPath,Language,DigitalProductID}
  #      — the engine reads these at startup.
  #   7. `tar --zstd` of the merged tree.
  #
  # NB: SETUP.EXE on the retail CD cannot run silently (its UI prompts
  # for a CD key) and the agent harness can't drive interactive Wine
  # dialogs, so the bake skipped running SETUP.EXE itself and instead
  # reproduced every filesystem effect SETUP.EXE would have written.
  # Additionally the bake ran `winetricks --unattended directplay` to
  # capture the native dpnet/dplayx/dpnh* DLLs and their COM CLSID
  # registrations into the install tree's `_strom/` staging dir; preRun
  # below applies those into the runtime wineprefix on first launch.
  src = fetchIpfs {
    cid = "QmWn94KUgDs59QMvs6sjyVQsXScRiwDzPnEJKbHn8EQxUN";
    hash = "sha256-OaeVhOACtGI1sInZZBuADk/N7c8/Buw/vMVroysa8A4=";
    name = "freelancer-install.tar.zst";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "freelancer";

  inherit src;

  ipfsSources = [ src ];

  nativeBuildInputs = [
    zstd
    gnutar
  ];

  buildScript = ''
    mkdir -p "$out"
    tar --zstd -xf "$src" -C "$out"
  '';

  runtime = "proton";
  executable = "exe/freelancer.exe";

  saveLocations = [ "Documents/My Games/Freelancer" ];

  copyGlobs = [
    "Accts/"
    "exe/PerfOptions.ini"
  ];

  env = {
    # DXVK d3d8/d3d9 are mandatory — without them Wine's wined3d wrapper
    # fails Freelancer's video-card detection branch. mfc42 native is
    # required so FLServer.exe can find the MS MFC42 in EXE/ instead of
    # hitting a missing-import death. DirectPlay overrides ensure the
    # native dpnet/dplayx that winetricks installs win over wine builtins.
    WINEDLLOVERRIDES = lib.concatStringsSep ";" [
      "d3d8=n,b"
      "d3d9=n,b"
      "mfc42=n,b"
      "mfc42u=n,b"
      "dplayx=n,b"
      "dpnet=n,b"
      "dpnhpast=n,b"
      "dpnhupnp=n,b"
      "dpmodemx=n,b"
      "dpwsockx=n,b"
    ];
  };

  preRun = ''
    PFX="$STROM_COMPATDATA/0/pfx"
    SYSREG="$PFX/system.reg"
    USERREG="$PFX/user.reg"

    # Seed Freelancer install-path registry keys on first run, once the
    # proton bootstrap has populated system.reg. The engine reads HKLM\
    # Software\Microsoft\Microsoft Games\Freelancer\1.0\{AppPath,DataPath,
    # InstallPath} at startup; without them Freelancer.exe refuses to
    # advance past load_main(). GAMEDIR_WIN is the in-prefix Z: path that
    # maps to the fuse-overlayfs $GAMEDIR.
    if [ -f "$SYSREG" ] \
        && ! grep -q 'Microsoft Games\\\\Freelancer\\\\1.0' "$SYSREG"; then
      GAMEDIR_WIN="Z:''${GAMEDIR//\//\\\\}"
      TS=$(date +%s)
      {
        printf '\n[Software\\\\Microsoft\\\\Microsoft Games] %s\n' "$TS"
        printf '\n[Software\\\\Microsoft\\\\Microsoft Games\\\\Freelancer] %s\n' "$TS"
        printf '\n[Software\\\\Microsoft\\\\Microsoft Games\\\\Freelancer\\\\1.0] %s\n' "$TS"
        printf '"AppPath"="%s\\\\exe\\\\"\n' "$GAMEDIR_WIN"
        printf '"DataPath"="%s\\\\data\\\\"\n' "$GAMEDIR_WIN"
        printf '"InstallPath"="%s\\\\"\n' "$GAMEDIR_WIN"
        printf '"Language"=dword:00000409\n'
        printf '"DigitalProductID"=hex:a4,00,00,00,03,00,00,00,'
        printf '33,33,33,33,33,2d,33,33,33,33,33,2d,33,33,33,33,33,2d,'
        printf '33,33,33,33,33,2d,33,33,33,33,33'
        for _ in $(seq 1 159); do printf ',00'; done
        printf '\n'
      } >>"$SYSREG"
    fi

    # DirectPlay 9.0c native + COM registration. Freelancer.exe and
    # FLServer.exe coordinate via an in-process DirectPlay session;
    # wine's builtin dpnet stub doesn't register the COM CLSIDs
    # Freelancer.exe needs to find the session, so it exits early after
    # spawning FLServer (only the FLServer console remains). The bake
    # tarball includes pre-extracted native DirectPlay 9.0c DLLs +
    # MFC42.DLL under _strom/ along with a directplay.reg snapshot of
    # the regsvr32-published CLSID/Interface entries from the bake's
    # wineprefix. Drop those into syswow64 and append the .reg snapshot
    # to system.reg on first launch (sentinel-gated). This bypasses the
    # need to invoke wine/winetricks from preRun (preRun runs outside
    # the proton FHS chroot, so proton's wine binary can't resolve its
    # 32-bit interpreter `/lib/ld-linux.so.2`).
    DP_SENTINEL="$PFX/.strom-directplay-registered"
    SYSWOW64="$PFX/drive_c/windows/syswow64"
    if [ -d "$SYSWOW64" ] && [ ! -e "$DP_SENTINEL" ]; then
      echo "[strom] freelancer: dropping native DirectPlay 9.0c + MFC42"
      for f in dpnet.dll dplayx.dll dpnhpast.dll dpnhupnp.dll \
               dpmodemx.dll dpwsockx.dll mfc42.dll; do
        if [ -f "$GAMEDIR/_strom/$f" ]; then
          # Move wine's builtin aside, then replace with the native one
          # the bake captured from the MS DX9 + VC6 redistributables.
          if [ -e "$SYSWOW64/$f" ] || [ -L "$SYSWOW64/$f" ]; then
            mv -f "$SYSWOW64/$f" "$SYSWOW64/$f.builtin" 2>/dev/null || true
          fi
          cp "$GAMEDIR/_strom/$f" "$SYSWOW64/$f"
        fi
      done
      # Append the DirectPlay COM CLSID/Interface registrations the
      # bake captured from `regsvr32 dpnet.dll dplayx.dll dpnhpast.dll
      # dpnhupnp.dll`. system.reg uses wine's native format, which is
      # also what the bake's directplay.reg snapshot is in — we can
      # append it verbatim.
      if [ -f "$GAMEDIR/_strom/directplay.reg" ]; then
        # Strip the WINE REGISTRY header (only valid at the top of a
        # .reg file). The remainder is `[section] time\n` blocks that
        # append cleanly after the existing system.reg content.
        tail -n +3 "$GAMEDIR/_strom/directplay.reg" >> "$SYSREG"
      fi
      touch "$DP_SENTINEL"
    fi

    # Save symlink: the runtime sets up $STROM_GAMEDIR↔$HOME bindings;
    # Freelancer writes pilots under My Documents\My Games\Freelancer.
    # saveLocations relocation in lib/proton.nix moves the in-prefix
    # path to $STROM_GAMEDIR. cd into exe/ so the engine's
    # `data path = ..\data` resolves relative to its CWD.
    cd "$GAMEDIR/exe"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      # Force relative-motion grab for in-flight mouse look (cockpit
      # rotation). Without this gamescope leaks Xwayland absolute
      # positions through SDL_SetRelativeMouseMode.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Freelancer (Digital Anvil 2003 retail install + FLHDE 0.7.1, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "freelancer";
  };
}
