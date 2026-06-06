{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # Blood Omen: Legacy of Kain (Silicon Knights / Crystal Dynamics 1996; the
  # Semi Logic Win32 port, 1997). GOG re-release v1.0 hotfix build 50548,
  # distributed as a single RAR by the blood-omen-legacy-of-kain-gog archive.
  # The RAR holds the GOG Inno Setup installer
  # setup_blood_omen_legacy_of_kain_1.0_hotfix_(50548).exe (plus concept art
  # and a 1.0->hotfix patch exe we ignore). innoextract --gog yields the game
  # tree at the root: Kain.exe (native Win32 binary), the Kain/ data dir
  # (.JAM movies, .VAG audio, PILL.BIG), Cfg/ config, plus GOG's own bundled
  # DirectDraw/DirectInput wrapper (ddraw.dll, dinput.dll, dixi.ini) and the
  # dxcfg graphics tool.
  #
  # Unlike most DirectDraw-era ports, GOG does NOT wrap this in DOSBox: Kain.exe
  # runs natively and GOG ships its own 1.5 MiB ddraw.dll + 364 KiB dinput.dll
  # shim (dixi.ini configures gamepad->DirectInput remapping) that makes the
  # game render and take input on modern Windows. We keep that shim and force
  # both DLLs native under Proton so Wine loads GOG's wrapper instead of its
  # builtin ddraw/dinput - the same arrangement the sibling Soul Reaver package
  # uses. (Verok's KainGL OpenGL wrapper is the alternative DirectDraw fix, but
  # it targets the raw retail CD and would collide with GOG's shim; left as a
  # fallback if GOG's ddraw misbehaves under Proton.)
  src = fetchIpfs {
    cid = "QmUB18G41smnpTJUE3sb3YjZstM1kxB9BU2V8X3ChtDNKk";
    fallbackUrl = "https://archive.org/download/blood-omen-legacy-of-kain-gog/Blood%20Omen%20Legacy%20of%20Kain%20%28GOG%29.rar";
    hash = "sha256-bnYOFtA5HFtu8zQmgbQrffxIfv6hj5oZibwhyizKxKs=";
    name = "blood-omen-legacy-of-kain-gog.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "blood-omen-legacy-of-kain";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"

    unar -o "$TMPDIR/rar" "$src"
    innoextract --gog -d "$TMPDIR/iss" \
      "$TMPDIR/rar"/*/setup_blood_omen_legacy_of_kain_*.exe
    cp -r "$TMPDIR/iss"/. "$out"/

    # GOG installer debris + Galaxy bits: not needed at runtime. The actual
    # game (Kain.exe + Kain/ + Cfg/ + GOG's ddraw/dinput shim + dxcfg) lives at
    # the $out root.
    rm -rf "$out/app" "$out/__redist" "$out/__support" "$out/tmp" \
           "$out/commonappdata"
    rm -f "$out"/goggame-*.info "$out"/goggame-*.hashdb \
          "$out"/goggame-*.script "$out"/goggame-*.id \
          "$out"/galaxy_*.exe "$out"/autorun.exe "$out"/autorun.inf || true

    chmod -R u+w "$out"
  '';

  runtime = "proton";

  # Saves persist via the per-game fuse-overlayfs upper (the GOG build writes
  # its saves under the game's own Saves/ next to Kain.exe, not under
  # drive_c/users/steamuser/...).
  saveLocations = [ ];
  executable = "Kain.exe";

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

  env = {
    STEAM_COMPAT_CONFIG = "sdlinput";
    # Force GOG's bundled DirectDraw/DirectInput wrapper DLLs native so Wine
    # loads them instead of its builtin ddraw/dinput (mirrors Soul Reaver).
    WINEDLLOVERRIDES = "ddraw,dinput=n,b";
  };

  meta = {
    description = "Blood Omen: Legacy of Kain (Silicon Knights / Crystal Dynamics 1996, GOG, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "blood-omen-legacy-of-kain";
  };
}
