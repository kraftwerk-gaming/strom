{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
  unzip,
  autoPatchelfHook,
  stdenv,
}:

let
  # GOG Linux release of Crypt of the NecroDancer (v4.1.0 build 5142
  # 72401) packaged as a 7z bundle that contains the main mojosetup .sh
  # installer plus three DLC installers (Amplified, Hatsune Miku, and
  # Synchrony). Each .sh is a mojosetup self-extracting installer
  # (shell-script header + zip), so unzip handles them directly once 7z
  # has unpacked the outer wrapper. The 64-bit binary is
  # NecroDancer.x64; lib/ holds the bundled SFML, FLAC, luajit,
  # libnecrolevel, plus the unused GOG Galaxy / Steam / Discord SDK
  # shims that the binary still links against.
  installer = fetchIpfs {
    cid = "Qmd7xoWXSrACjnnwtDKGWwL9e5dACs4wUiDCvxq576xhs9";
    fallbackUrl = "https://archive.org/download/lotsa-games-linux/Crypt%20of%20the%20NecroDancer%20GOG%20Linux.7z";
    hash = "sha256-TX/dD/FkrV1gCBH4RFiSMUXbLvvRnGGXfU47r0tPAeI=";
    name = "crypt-of-the-necrodancer-gog-linux.7z";
  };

  gameData = stdenv.mkDerivation {
    pname = "crypt-of-the-necrodancer-data";
    version = "4.1.0-72401";

    dontUnpack = true;

    nativeBuildInputs = [
      p7zip
      unzip
      autoPatchelfHook
      pkgs.jq
    ];

    # NecroDancer.x64 links against libfreetype/libGL/libX*/libudev plus
    # the bundled SFML/FLAC/luajit stack in lib/. libsfml-audio pulls in
    # OpenAL at load time.
    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      freetype
      openal
      libcap
      libuuid
      udev
      xorg.libX11
      xorg.libXcursor
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXScrnSaver
      xorg.libXxf86vm
    ];

    installPhase = ''
      runHook preInstall

      # Stage 1: unpack the outer 7z. It contains the main installer
      # and a dlcs/ directory with the three DLC installers.
      7z x -y ${installer} >/dev/null
      cd "Crypt of the NecroDancer GOG Linux"

      mkdir -p "$out"

      # Stage 2: extract the main game payload from the base installer.
      # GOG layout: data/noarch/game/{NecroDancer64/,data/} — the
      # binary + bundled libs live in NecroDancer64/, and the game
      # assets (entities/, level/, music/, sounds/, sounds_streaming/,
      # items/, gui/, lua/, mainmenu/, particles/, spells/, swipes/,
      # text/, …) live in the sibling data/ directory. Extract BOTH;
      # the engine's config.json mounts ../data at virtual path "ext"
      # (see external.mountPoints), and ext/level/*.png, ext/music/*.ogg
      # etc. are how the engine looks up the base-game assets.
      # Amplified and Hatsune Miku ship pure data/ overlays;
      # Synchrony ships a newer NecroDancer64/ (binary + .wsp + a
      # Synchrony.necromod marker in dlc/). Install Synchrony LAST so
      # its NecroDancer64/ overrides the base.
      unzip -q -o crypt_of_the_necrodancer_4_1_0_b5142_72401.sh \
        'data/noarch/game/NecroDancer64/*' 'data/noarch/game/data/*' || true
      unzip -q -o dlcs/crypt_of_the_necrodancer_amplified_4_1_0_b5142_72401.sh \
        'data/noarch/game/data/*' || true
      unzip -q -o dlcs/crypt_of_the_necrodancer_hatsune_miku_character_4_1_0_b5142_72401.sh \
        'data/noarch/game/data/*' || true
      unzip -q -o dlcs/crypt_of_the_necrodancer_synchrony_4_1_0_b5142_72401.sh \
        'data/noarch/game/NecroDancer64/*' || true

      # Lay out $out as: NecroDancer64/ payload at the top level + the
      # game-data tree under $out/data/. The engine's config.json
      # default external.path is ".." (it expects CWD to be
      # NecroDancer64/ inside GOG's <install>/game/). We CWD into $out
      # itself, so patch external.path to "." and the mountPoint
      # "source":"data" then resolves ext/* to $out/data/*.
      cp -r data/noarch/game/NecroDancer64/. "$out"/
      cp -r data/noarch/game/data "$out"/data

      # GOG-supplied "NecroDancer" launcher script does cd + LD_LIBRARY_PATH
      # itself, but we want a single binary entry-point that scopes
      # LD_LIBRARY_PATH to the game only (so the bundled libs don't leak
      # into gamescope). Replace it with our own wrapper below.
      rm -f "$out/NecroDancer"
      chmod +x "$out/NecroDancer.x64"

      # Patch config.json's external.path from ".." to "." so the
      # virtual-filesystem mount points (ext -> data, ext/dungeons ->
      # dungeons, etc.) resolve relative to $out instead of $out/..
      # (which would otherwise dereference into a nix-store parent).
      jq '.wos.game.assets.external.path = "."' \
        "$out/config.json" > "$out/config.json.new"
      mv "$out/config.json.new" "$out/config.json"

      # Wrap the binary so the bundled SFML/FLAC/luajit in lib/ are
      # LD_LIBRARY_PATH-visible only to the game process. Mirrors the
      # hotline-miami-2 / carrion approach.
      mv "$out/NecroDancer.x64" "$out/NecroDancer.x64-bin"
      cat > "$out/NecroDancer.x64" <<'EOF'
      #!/bin/sh
      here="$(dirname "$0")"
      cd "$here"
      exec env LD_LIBRARY_PATH="$here/lib" "$here/NecroDancer.x64-bin" "$@"
      EOF
      chmod +x "$out/NecroDancer.x64"

      runHook postInstall
    '';

    # autoPatchelf needs to find the bundled SFML/FLAC/luajit/libnecrolevel
    # alongside each other so cross-references resolve. Register $out/lib
    # before autoPatchelf walks ELFs.
    preFixup = ''
      addAutoPatchelfSearchPath "$out/lib"
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "crypt-of-the-necrodancer";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  runtime = "native";
  executable = "NecroDancer.x64";

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "Crypt of the NecroDancer (native Linux, GOG v4.1.0 build 5142, + Amplified / Hatsune Miku / Synchrony DLCs)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "crypt-of-the-necrodancer";
  };
}
