{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  openjk,
}:

let
  # Retail 2002 LucasArts/Raven CD ISO. The disc lays the game's pk3
  # assets out under GameData/GameData/base/ (assets0..2.pk3 +
  # assets5.pk3), so we can copy that base/ directly into the build
  # output and skip the InstallShield setup entirely.
  src = fetchIpfs {
    cid = "QmbBSGrnxrRM47oVLkomqJkuZAKnamq2V1Rgjga6EyN4H1";
    fallbackUrl = "https://archive.org/download/star-wars-jedi-knight-2-jedi-outcast/JediKnight2-jedioutcast.7z";
    hash = "sha256-y51uDKW1KJKTivNH5aDQXetBPAXmnAsU+BqvPpSAG6A=";
    name = "JediKnight2-jedioutcast.7z";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "star-wars-jedi-knight-ii-jedi-outcast";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  # Two-level unpack: the .7z wraps an ISO, the ISO holds the
  # GameData/GameData/base/ pak tree. Pull the inner base/ folder out
  # of the ISO so the openjo engine finds assets0..2.pk3 + assets5.pk3
  # alongside the binary at runtime.
  buildScript = ''
    mkdir -p "$out/base" "$out/OpenJK"
    7z x -y "$src" -o"$TMPDIR/sevenz"
    7z x -y "$TMPDIR/sevenz/JediKnight2-jedioutcast.iso" \
      -o"$TMPDIR/iso" 'GameData/GameData/base/*'
    cp "$TMPDIR/iso/GameData/GameData/base"/*.pk3 "$out/base/"
    # openjo_sp.x86_64 dlopens its renderer + game module relative to
    # fs_basepath: rd<r>_<x>.so directly in basepath, jospgame<arch>.so
    # in basepath/OpenJK/. The libs ship in the openjk.openjo output
    # but aren't on dlopen's search path unless we materialise them
    # next to the pak data.
    ln -s ${openjk.openjo}/opt/JediOutcast/rdjosp-vanilla_x86_64.so "$out/"
    ln -s ${openjk.openjo}/opt/JediOutcast/OpenJK/jospgamex86_64.so "$out/OpenJK/"
    chmod -R u+w "$out"
  '';

  # Use the OpenJK community engine's openjo single-player binary
  # (jedi outcast fork). It loads the retail pak files from a `base/`
  # directory relative to fs_basepath, skips the original CD check,
  # and runs natively without Proton/wine. The engine + rdjosp /
  # jospgame modules live in the openjk multi-output `openjo` slot;
  # the default `out` only ships symlinks under bin/.
  runtime = "native";
  executable = "${openjk.openjo}/opt/JediOutcast/openjo_sp.x86_64";
  # mk-game.nix `cd "$GAMEDIR"` before launch, so fs_basepath="."
  # points the engine at our overlaid install dir (where base/ lives).
  # fs_homepath defaults to ~/.local/share/openjo inside the sandbox,
  # which lands under $STROM_GAMEDIR via the native runtime's
  # $HOME=>$STROM_GAMEDIR bind.
  # +set r_mode -1 enables custom resolution; r_customwidth/height
  # forces 1920x1080 to fill the gamescope window (openjo defaults to
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
    description = "Star Wars Jedi Knight II: Jedi Outcast (LucasArts/Raven 2002, retail CD via OpenJK openjo)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "star-wars-jedi-knight-ii-jedi-outcast";
  };
}
