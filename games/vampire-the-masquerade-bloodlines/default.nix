{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unar,
  innoextract,
}:

let
  # GOG Bloodlines + Wesp's Unofficial Patch 11.5 (community fixes for the
  # 2004 release). The download is a rar wrapping the GOG Inno Setup .exe
  # plus its .bin slot 1.
  src = fetchIpfs {
    cid = "QmZeWvEYsmPkqRVs2aX6vEB8jdQB2982aB1Ej7rb5DBFAR";
    fallbackUrl = "https://archive.org/download/the-vampire-the-maquerade-collection/The%20Vampire%20the%20Masquerade%20Collection/Vampire%20the%20Masquerade%20-%20Bloodlines%20-%20Unofficial%20Patch%20-%20Offical%20GOG%20Installer%20-%20%28Version%20-%2082662%29.rar";
    hash = "sha256-3XTFyfUzPUMV+uTIkIyQ/B8KiDcHP4PFE7Kjmm7ija4=";
    name = "vampire-the-masquerade-bloodlines.rar";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "vampire-the-masquerade-bloodlines";

  inherit src;

  nativeBuildInputs = [
    unar
    innoextract
  ];

  buildScript = ''
    mkdir -p "$out"
    unar -o "$TMPDIR/rar" "$src"
    cd "$TMPDIR/rar/VTMB-UnofficialPatch" || cd "$TMPDIR/rar"/*
    innoextract --gog -d "$TMPDIR/iss" \
      "setup_vampire_the_masquerade_-_bloodlinestm_-_unofficial_patch_up_11.5_(82662).exe"
    # innoextract drops most game files at the root; only goggame icons
    # and Vampire/cfg/ live under app/. tmp/, __redist/, commonappdata/
    # are install-time scaffolding.
    for f in Bin Docs Loader.dll Loader.exe Unofficial_Patch VTMBup-loader.txt \
             VTMBup-readme.txt Vampire Vampire.exe Vampire.exe.12 Version.inf \
             manual.pdf goggame-1265943179.hashdb goggame-1265943179.info; do
      cp -r "$TMPDIR/iss/$f" "$out/"
    done
    # Merge app/Vampire/cfg/ (extra config from GOG) into Vampire/cfg/.
    cp -r "$TMPDIR/iss/app/Vampire/cfg/." "$out/Vampire/cfg/"
  '';

  runtime = "proton";
  # Loader.exe is the Unofficial Patch launcher; it sets up
  # game-specific patch flags and then calls Vampire.exe.
  executable = "Loader.exe";

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

  preRun = ''
    export PROTON_LOG=1
    export PROTON_LOG_DIR="$STROM_CACHEDIR"
  '';

  meta = {
    description = "Vampire: The Masquerade — Bloodlines (GOG + Unofficial Patch 11.5, via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "vampire-the-masquerade-bloodlines";
  };
}
