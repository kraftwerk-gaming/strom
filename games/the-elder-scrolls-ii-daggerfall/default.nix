{
  self,
  lib,
  pkgs,
  fetchIpfs,
  fetchurl,
  unzip,
}:

let
  # Bethesda freeware release of the original 1996 DOS Daggerfall, made
  # free in 2009. We don't run FALL.EXE — Daggerfall Unity reuses the
  # ARENA2 game files (textures, maps, sounds, quests) and replaces the
  # engine.
  gameData = fetchIpfs {
    cid = "QmPPaCz8XMebVU5Hm4S37PiABjXRB85dopX1Am3TESFB4H";
    fallbackUrl = "https://archive.org/download/msdos_Elder_Scrolls_The_-_Daggerfall_1996/Elder_Scrolls_The_-_Daggerfall_1996.zip";
    hash = "sha256-IRhHLvfk1PZGiKn0FNljJ+F7yZ3UxNb+k0CBKyEuOzM=";
    name = "the-elder-scrolls-ii-daggerfall.zip";
  };

  # Daggerfall Unity 1.1.1 (Oct 2025 security-update build) by
  # Interkarma / Daggerfall Workshop — open-source Unity rewrite of the
  # 1996 engine. Native Linux 64-bit ELF. Released under the MIT licence;
  # consumes the freeware ARENA2 data above.
  dfu = fetchurl {
    url = "https://github.com/Interkarma/daggerfall-unity/releases/download/v1.1.1-cve-2025/dfu_linux_64bit-v1.1.1.zip";
    hash = "sha256-vjxHaukpcvQkSHV3GSZq2CwEho63tvOjyQ/PzxSQhJo=";
    name = "dfu-linux-64bit-1.1.1.zip";
  };

  # Pre-cooked settings.ini that points DFU at the bundled game files and
  # suppresses the "Setup Game Wizard" launcher. `MyDaggerfallPath` is
  # the parent of `arena2/` (DFU's TestArena2Exists does
  # `Path.Combine(parent, "arena2")`), so we point it at $GAMEDIR/data,
  # not $GAMEDIR/data/arena2. `[GUI] ShowOptionsAtStart=False` keeps the
  # wizard from showing on subsequent launches; combined with a valid
  # MyDaggerfallPath, DFU's startup branch (`SceneControl.cs:46`) loads
  # the main menu directly. `GAMEDIR_PLACEHOLDER` is rewritten in
  # runScript once $GAMEDIR is known.
  settingsIni = pkgs.writeText "settings.ini" ''
    [Daggerfall]
    MyDaggerfallPath=GAMEDIR_PLACEHOLDER/data

    [GUI]
    ShowOptionsAtStart=False
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-elder-scrolls-ii-daggerfall";

  src = dfu;

  ipfsSources = [
    dfu
    gameData
  ];

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out/dfu" "$out/data"
    unzip -q ${dfu} -d "$out/dfu"
    unzip -q ${gameData} -d /tmp/df
    cp -r /tmp/df/ESdagger/. "$out/data/"
    chmod +x "$out/dfu/DaggerfallUnity.x86_64"
  '';

  runtime = "custom";

  # Unity 2019 LTS runtime expects an FHS layout. The Unity player loads
  # libGL/libudev/etc by bare name via dlopen, so add the graphics and
  # input stack here. The strom mk-game custom branch already routes the
  # game through fhs-user-env + bwrap; targetPkgs is what populates the
  # FHS chroot's /usr/lib.
  targetPkgs = p: [
    p.glibc
    p.libgcc
    p.libGL
    p.mesa
    p.vulkan-loader
    p.alsa-lib
    p.libpulseaudio
    p.openal
    p.libx11
    p.libxext
    p.libxcursor
    p.libxi
    p.libxrandr
    p.libxinerama
    p.libxrender
    p.libxfixes
    p.libxcomposite
    p.libxxf86vm
    p.libxkbcommon
    p.fontconfig
    p.freetype
    p.zlib
    # Unity Mono runtime loads libudev for the new input system.
    p.systemd
  ];

  # DFU's Unity persistentDataPath on Linux is
  # ~/.config/unity3d/Daggerfall Workshop/Daggerfall Unity/. The strom
  # custom runtime binds $HOME → $STROM_GAMEDIR, so that subtree lives
  # in ~/.strom/the-elder-scrolls-ii-daggerfall/ on the host. We
  # pre-seed settings.ini there with the right ARENA2 path on every
  # launch (cheap; settings.ini is tiny) so DFU skips its first-run
  # launcher.
  runScript = ''
    CFG_DIR="$HOME/.config/unity3d/Daggerfall Workshop/Daggerfall Unity"
    mkdir -p "$CFG_DIR"
    sed "s|GAMEDIR_PLACEHOLDER|$GAMEDIR|" ${settingsIni} > "$CFG_DIR/settings.ini"
    exec "$GAMEDIR/dfu/DaggerfallUnity.x86_64"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "The Elder Scrolls II: Daggerfall (Bethesda 1996, via Daggerfall Unity)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-elder-scrolls-ii-daggerfall";
  };
}
