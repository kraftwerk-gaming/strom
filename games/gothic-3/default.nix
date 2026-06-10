{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  innoextract,
  cabextract,
}:

let
  # Microsoft DirectX End-User Runtime (February 2010 redistributable). The
  # native d3dx9 DLLs Gothic 3 needs live in per-version nested cabinets inside
  # this self-extracting redist (e.g. d3dx9_40.dll is in Nov2008_d3dx9_40_x86.cab).
  # Same package (and hash) as Gothic II uses for its DirectMusic set.
  directxFeb2010 = fetchurl {
    url = "https://web.archive.org/web/20100205120000id_/https://download.microsoft.com/download/E/E/1/EE17FF74-6C45-4575-9CF4-7FC2597ACD18/directx_feb2010_redist.exe";
    hash = "sha256-9tGR6JqWPXzKNPFp0w9J6rmcHtO7ktpz7ENhfKqh6T8=";
    name = "directx_feb2010_redist.exe";
  };

  # Native d3dx9 DLLs (the winetricks `d3dx9` verb). Wine's builtin d3dx9 ships
  # a STUB effect compiler -- ID3DXEffectCompilerImpl_CompileEffect logs
  # "stub!" and never produces bytecode -- so Gothic 3's Genome engine hangs
  # forever at the "Compile shader material cache... Press button to start"
  # dialog after OK (the effect-shader compile never completes, the menu is
  # never reached). Engine.dll imports d3dx9_40.dll specifically; we inject the
  # full available 24..42 range (each shipped in its own datestamped cab inside
  # the Feb-2010 redist) so the CP and any mods that pull a different version
  # also resolve. d3dx9_43 is NOT in the Feb-2010 redist (it first shipped in
  # the June-2010 one) and Gothic 3 does not import it, so 42 is the ceiling.
  d3dx9Cabs = {
    "d3dx9_24" = "Feb2005_d3dx9_24_x86.cab";
    "d3dx9_25" = "Apr2005_d3dx9_25_x86.cab";
    "d3dx9_26" = "Jun2005_d3dx9_26_x86.cab";
    "d3dx9_27" = "Aug2005_d3dx9_27_x86.cab";
    "d3dx9_28" = "Dec2005_d3dx9_28_x86.cab";
    "d3dx9_29" = "Feb2006_d3dx9_29_x86.cab";
    "d3dx9_30" = "Apr2006_d3dx9_30_x86.cab";
    "d3dx9_31" = "OCT2006_d3dx9_31_x86.cab";
    "d3dx9_32" = "DEC2006_d3dx9_32_x86.cab";
    "d3dx9_33" = "APR2007_d3dx9_33_x86.cab";
    "d3dx9_34" = "JUN2007_d3dx9_34_x86.cab";
    "d3dx9_35" = "AUG2007_d3dx9_35_x86.cab";
    "d3dx9_36" = "Nov2007_d3dx9_36_x86.cab";
    "d3dx9_37" = "Mar2008_d3dx9_37_x86.cab";
    "d3dx9_38" = "JUN2008_d3dx9_38_x86.cab";
    "d3dx9_39" = "Aug2008_d3dx9_39_x86.cab";
    "d3dx9_40" = "Nov2008_d3dx9_40_x86.cab";
    "d3dx9_41" = "Mar2009_d3dx9_41_x86.cab";
    "d3dx9_42" = "Aug2009_d3dx9_42_x86.cab";
  };
  d3dx9Dlls = lib.attrNames d3dx9Cabs;

  # Gothic 3 (Piranha Bytes 2006, Genome-engine action RPG). GOG offline
  # installer v1.75.14L build 21829, English/Russian language variant. Split
  # InnoSetup bundle:
  #   setup_gothic_3_1.75.14l_(21829).exe    --  807 KiB InnoSetup stub
  #   setup_gothic_3_1.75.14l_(21829)-1.bin  -- 3.26 GiB game-data slob
  # innoextract --gog reads the .exe stub header and pulls the data out of the
  # paired .bin slice; the two files must sit in the same directory with
  # matching base names (stub base == bin base minus "-1").
  #
  # No stable single-file public HTTP mirror exists for this exact GOG build
  # (archive.org carries only a retail ISO and the Forsaken Gods expansion
  # installer, not the base-game GOG offline installer); the only reliable
  # source is the "Gothic 3 GOG" torrent, whose ENG_RUS/ folder holds this
  # pair. fallbackUrl therefore points at the magnet; seed via IPFS after the
  # game is interactively tested.
  #
  # The GOG release already bundles the Gothic 3 Community Patch (CP) 1.75 --
  # the community-standard stability/quest fix set -- so no extra patch overlay
  # is needed at the staging step. (If runtime instability surfaces under
  # Proton, the CP "alternative AI"/QuickPatch tuning in ge3.ini may still need
  # adjusting, but that is a post-test concern, not a build-time one.)
  #
  # nix store path names forbid parentheses, so the fetchIpfs `name` drops the
  # "(21829)" build tag; the buildScript re-creates the real GOG basenames
  # (with the parens) as symlinks before innoextract, so --gog still pairs the
  # stub with its .bin slice.
  setupExe = fetchIpfs {
    cid = "QmVhehUcbAfHPmEkD2iZ6qBYCwXdd3SLeuDhtGvuWoGa18";
    fallbackUrl = "magnet:?xt=urn:btih:05172F55C251AE6959C9EF24108D15199964FDE9&dn=Gothic%203%20GOG";
    hash = "sha256-XwAfaco9+Y7vCXg131dxt22D7+u6JGSI80A2NSYAqQ8=";
    name = "setup_gothic_3_1.75.14l_21829.exe";
  };

  src = fetchIpfs {
    cid = "QmVcH9mzi6oCCmBFzpBTWjuWr5jjp6P9W7jmuUZYrRB2Lx";
    fallbackUrl = "magnet:?xt=urn:btih:05172F55C251AE6959C9EF24108D15199964FDE9&dn=Gothic%203%20GOG";
    hash = "sha256-BvVb/Db1S9KgeUZHWyd6wAIh5gn4nI+L4nUzs45811I=";
    name = "setup_gothic_3_1.75.14l_21829-1.bin";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gothic-3";

  inherit src;
  ipfsSources = [
    src
    setupExe
  ];

  nativeBuildInputs = [
    innoextract
    cabextract
  ];

  buildScript = ''
    mkdir -p "$out" "$TMPDIR/inno" "$TMPDIR/iss"

    # Re-pair the split installer under matching base names so innoextract
    # --gog can locate the .bin slice from the .exe stub header.
    ln -s "${setupExe}" "$TMPDIR/inno/setup_gothic_3_1.75.14l_(21829).exe"
    ln -s "$src"        "$TMPDIR/inno/setup_gothic_3_1.75.14l_(21829)-1.bin"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/inno/setup_gothic_3_1.75.14l_(21829).exe"

    # innoextract --gog strips the installer's app/ constant prefix, so the
    # real game tree (Gothic3.exe, the engine *.dll set, Data/, Ini/, the
    # bundled PhysXCore/PhysXLoader, fmodex/binkw32) lands at the extraction
    # ROOT. The leftover app/ holds only GOG metadata (snapshots, webcache,
    # the .ico); tmp/, __redist, commonappdata are installer-bootstrap junk.
    cp -r "$TMPDIR/iss"/. "$out"/
    chmod -R u+w "$out"
    rm -rf "$out/app" "$out/tmp" "$out/__redist" "$out/__support" \
           "$out/commonappdata"

    # Strip GOG-launcher / installer side files; the engine never reads them
    # at runtime (they only matter inside GOG Galaxy).
    rm -f "$out"/goggame-*.dll "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.script "$out"/goggame-*.ico "$out"/*.url \
          2>/dev/null || true

    # Native d3dx9 DLL set for the effect-compiler hang fix. The Feb-2010
    # redist is a self-extracting cabinet whose per-version members are
    # themselves cabinets; the actual d3dx9_NN.dll lives one level down. So
    # this is a two-stage cabextract: redist -> <date>_d3dx9_NN_x86.cab ->
    # d3dx9_NN.dll. preRun copies these into the prefix's syswow64.
    mkdir -p "$TMPDIR/dx" "$out/_strom/d3dx9"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (dll: cab: ''
        cabextract -q -d "$TMPDIR/dx" -F '${cab}' ${directxFeb2010}
        cabextract -q -d "$out/_strom/d3dx9" -F '${dll}.dll' "$TMPDIR/dx/${cab}"
      '') d3dx9Cabs
    )}
  '';

  runtime = "proton";

  # Gothic 3's Genome engine is a Direct3D9 renderer; Proton's DXVK handles it
  # without a native-ddraw/wined3d override (unlike the older DirectDraw7
  # Gothic 1/2 ZenGin games). The GOG build ships Community Patch 1.75, which
  # is the community-standard stability fix, so no engine-binary swap is
  # needed at build time.
  executable = "Gothic3.exe";

  # Gothic 3 writes savegames and UserOptions.ini under
  # %USERPROFILE%\Documents\Gothic 3\ (plus a Documents\gothic3\ shader cache),
  # i.e. under drive_c/users/steamuser/Documents -- the standard relocation
  # path, so the generic saveLocations handling applies.
  saveLocations = [
    "Documents/Gothic 3"
  ];

  # Genome is a single-threaded-ish 2006 D3D9 engine; the proton runtime's
  # default FHS already supplies its DXVK/X libs. Large-address-aware helps the
  # 32-bit engine address the full open world without the low-memory OOM the
  # vanilla 2006 binary hits.
  env = {
    WINE_LARGE_ADDRESS_AWARE = "1";
    # Force the native Microsoft d3dx9 DLLs (overlaid into syswow64 by preRun)
    # over Wine's builtin, whose effect compiler is a stub. n,b so a missing
    # DLL still falls back to builtin rather than refusing to load at all.
    WINEDLLOVERRIDES = lib.concatStringsSep ";" (map (d: "${d}=n,b") d3dx9Dlls);
  };

  # Drop the native d3dx9 DLLs into the wineprefix's syswow64 (the 32-bit
  # system dir Gothic 3's 32-bit Engine.dll loads from). Sentinel-gated so it
  # only fires once, after the prefix is initialised (system.reg exists). No
  # COM registration is needed: d3dx9 is a plain import DLL, not a COM server.
  preRun = ''
    PFX="$STROM_COMPATDATA/0/pfx"
    SYSWOW64="$PFX/drive_c/windows/syswow64"
    D3DX9_SENTINEL="$PFX/.strom-d3dx9-installed"

    if [ -d "$SYSWOW64" ] && [ -f "$PFX/system.reg" ] \
        && [ ! -e "$D3DX9_SENTINEL" ]; then
      echo "[strom] gothic-3: installing native d3dx9 into wineprefix" >&2
      for f in ${lib.escapeShellArgs (map (d: "${d}.dll") d3dx9Dlls)}; do
        if [ -f "$GAMEDIR/_strom/d3dx9/$f" ]; then
          if [ -e "$SYSWOW64/$f" ] || [ -L "$SYSWOW64/$f" ]; then
            mv -f "$SYSWOW64/$f" "$SYSWOW64/$f.builtin" 2>/dev/null || true
          fi
          cp "$GAMEDIR/_strom/d3dx9/$f" "$SYSWOW64/$f"
        fi
      done
      touch "$D3DX9_SENTINEL"
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

  meta = {
    description = "Gothic 3 (Piranha Bytes 2006, GOG v1.75.14L build 21829 + Community Patch, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "gothic-3";
  };
}
