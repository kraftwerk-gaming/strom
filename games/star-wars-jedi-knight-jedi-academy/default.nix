{
  self,
  lib,
  pkgs,
  fetchIpfs,
  innoextract,
  openjk,
}:

let
  # GOG release of the 2003 LucasArts/Raven game, distributed as an
  # Inno Setup installer .exe (not a CD ISO). innoextract unpacks the
  # Inno archive without wine; GOG lays the game tree under app/, so
  # the pk3 assets live at app/GameData/base/ (assets0..3.pk3). We copy
  # that base/ directly into the build output and skip running setup.
  src = fetchIpfs {
    cid = "Qmf1ZzHJSbhz9T6sLWD8V41KafABwFdmSQJrSLRjGhAro6";
    fallbackUrl = "https://archive.org/download/setup_sw_jedi_academy_2.0.0.4_202508/Star%20Wars%20Jedi%20Knight%20Jedi%20Academy/setup_sw_jedi_academy_2.0.0.4.exe";
    hash = "sha256-Oo1/qqC/HfQRdQxrHGf5L+ZwcPdPU4UxttF8Z6IGCw4=";
    name = "setup_sw_jedi_academy_2.0.0.4.exe";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "star-wars-jedi-knight-jedi-academy";

  inherit src;

  nativeBuildInputs = [ innoextract ];

  # Unpack the Inno Setup installer, then pull the inner base/ folder
  # out of the GOG app/GameData/ tree so the openja engine finds
  # assets0..3.pk3 alongside the binary at runtime. -I limits extraction
  # to the base pak dir; the rest of the installer (movies, docs) is not
  # needed by the engine.
  buildScript = ''
    mkdir -p "$out/base" "$out/OpenJK"
    innoextract -s -I "GameData/base" -d "$TMPDIR/ja" "$src"
    cp "$TMPDIR/ja/app/GameData/base"/*.pk3 "$out/base/"
    # openjk_sp.x86_64 dlopens its renderer + game module relative to
    # fs_basepath: rdsp-vanilla_x86_64.so directly in basepath,
    # jagamex86_64.so in basepath/OpenJK/. The libs ship in the
    # openjk.openja output but aren't on dlopen's search path unless we
    # materialise them next to the pak data.
    ln -s ${openjk.openja}/opt/JediAcademy/rdsp-vanilla_x86_64.so "$out/"
    ln -s ${openjk.openja}/opt/JediAcademy/OpenJK/jagamex86_64.so "$out/OpenJK/"
    chmod -R u+w "$out"
  '';

  # Use the OpenJK community engine's openja single-player binary
  # (jedi academy fork). It loads the retail pak files from a `base/`
  # directory relative to fs_basepath, skips the original disc check,
  # and runs natively without Proton/wine. The engine + rdsp-vanilla /
  # jagame modules live in the openjk multi-output `openja` slot; the
  # default `out` only ships symlinks under bin/.
  runtime = "native";
  executable = "${openjk.openja}/opt/JediAcademy/openjk_sp.x86_64";
  # mk-game.nix `cd "$GAMEDIR"` before launch, so fs_basepath="."
  # points the engine at our overlaid install dir (where base/ lives).
  # fs_homepath defaults to ~/.local/share/openjk inside the sandbox,
  # which lands under $STROM_GAMEDIR via the native runtime's
  # $HOME=>$STROM_GAMEDIR bind.
  # +set r_mode -1 enables custom resolution; r_customwidth/height
  # forces 1920x1080 to fill the gamescope window (openja defaults to
  # 640x480 windowed, which renders a quarter-sized image inside the
  # 1080p nested compositor).
  executableArgs = [
    "+set"
    "fs_basepath"
    "."
    "+set"
    "r_mode"
    "-1"
    "+set"
    "r_customwidth"
    "1920"
    "+set"
    "r_customheight"
    "1080"
    "+set"
    "r_fullscreen"
    "1"
  ];

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
    description = "Star Wars Jedi Knight: Jedi Academy (2003 LucasArts/Raven, OpenJK engine, native)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "star-wars-jedi-knight-jedi-academy";
  };
}
