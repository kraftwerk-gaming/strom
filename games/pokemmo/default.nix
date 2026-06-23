{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
}:

# PokeMMO is a fan-made multiplayer Pokemon client. The Java launcher
# itself is freely distributed by the developers; the Nintendo game ROMs
# are sourced separately and baked into the overlay so the client boots
# straight to the login screen with all regions detected.
#
# How PokeMMO detects ROMs (verified by decompiling PokeMMO.exe with CFR):
#   * On startup the client reads `config/main.properties` (relative to
#     its working directory, which strom sets to the fuse-overlayfs merge
#     root = ~/.strom/pokemmo/). The `client.roms.*` keys point at the ROM
#     files; when every referenced file is present and validates, the
#     client skips the in-game "rom-panel" (Locate ROMs) screen entirely
#     and proceeds to account login.
#   * The scanned folder is `roms/`; expected filenames are fixed
#     (pokemon_black.nds / pokemon_firered.gba / pokemon_emerald.gba /
#     pokemon_platinum.nds / pokemon_heartgold.nds). This matches the
#     PortMaster port's config (lowlevel-1989/pokemmo-port).
#   * Validation is by the cartridge GAME CODE in the ROM header + version
#     byte, NOT a whole-file CRC32. The gen3 table (class f/A41) maps e.g.
#     "BPRE" v0/v1 -> Fire Red USA, "BPEE" v0 -> Emerald USA; the NDS
#     games are matched by their header game code (IRAO White-USA,
#     IRBO Black-USA, CPUE Platinum-USA, IPKE HeartGold-USA). Any clean
#     No-Intro USA dump with the right header code therefore validates.
#
# Region coverage with the baked set:
#   White (IRAO, USA)         -> Unova       [mandatory base ROM]
#   Fire Red v1.1 (BPRE, USA) -> Kanto
#   Emerald (BPEE, USA)       -> Hoenn
#   Platinum (CPUE, USA)      -> Sinnoh
#   HeartGold (IPKE, USA)     -> Johto
#
# Account registration on https://pokemmo.com/ is required to log in.

let
  src = fetchIpfs {
    cid = "QmP6QZebT27cydKwg2fs6qBJw52qnk7TYniKoNbzVEfBFo";
    fallbackUrl = "https://dl.pokemmo.com/PokeMMO-Client.zip?r=31914";
    hash = "sha256-8foFB6p3K0Ija9ZQ+oam1tcGFka4wSJSOOOvtr6ydbU=";
    name = "pokemmo-client.zip";
  };

  # Nintendo game ROMs. PokeMMO matches these by the game code embedded in
  # each ROM header (see comment above), so these specific clean No-Intro
  # USA dumps are accepted as-is. Renamed at build time to the fixed
  # filenames the client's config keys reference.
  roms = {
    # MANDATORY base ROM. Pokemon White Version (USA), game code IRAO.
    white = fetchIpfs {
      cid = "QmavUhtUyGRnT4vNRPGCuMuZxvAusA4ZcqJfG7ATy5pS4i";
      fallbackUrl = "https://archive.org/download/scxnds_202207/Pokemon%20-%20White%20Version%20%28DSi%20Enhanced%29%28USA%29%20%28E%29%28SweeTnDs%29.nds/5584%20-%20Pokemon%20-%20White%20Version%20%28DSi%20Enhanced%29%28USA%29%20%28E%29%28SweeTnDs%29.nds";
      hash = "sha256-k+T0c86aBUO8zy5ons0Hq0/MOd0A+08ZQ0PL1ecOF+0=";
      name = "pokemon-white-usa.nds";
    };
    # Pokemon Fire Red Version (USA) (Rev 1), game code BPRE v1.
    firered = fetchIpfs {
      cid = "QmcJuHrudsqmmexuCmt7259zZvGNPjP9smEiJwjq19rNqm";
      fallbackUrl = "https://archive.org/download/pokemon-fire-red-version-u-v-1.1/Pokemon%20-%20Fire%20Red%20Version%20%28U%29%20%28V1.1%29.gba";
      hash = "sha256-cpBBuUCv4DEwLWMP2+V8DBRfP3ttm47KXphnjQyk0Fk=";
      name = "pokemon-firered-usa.gba";
    };
    # Pokemon Emerald Version (USA, Europe), game code BPEE v0.
    emerald = fetchIpfs {
      cid = "QmVviHYSUADxgNNmkF1XqKxw8kAmxNBFnmHo6BE4AaA51R";
      fallbackUrl = "https://github.com/AlexBlackmore/roms/raw/master/gba/Pokemon%20-%20Emerald%20Version%20%28USA%2C%20Europe%29.gba";
      hash = "sha256-qd7ITf5/YqsiILr673R52gkp0Gbs4WpohfYibbGQha8=";
      name = "pokemon-emerald-usa.gba";
    };
    # Pokemon Platinum Version (USA), game code CPUE.
    platinum = fetchIpfs {
      cid = "QmStjHkYeC1NomWEVknoSzvBKdAL1TqqeaaGa4XK1sgAU6";
      fallbackUrl = "https://archive.org/download/scxnds_202207/Pokemon%20-%20Platinum%20Version%20%28v01%29%20%28U%29.nds/4998%20-%20Pokemon%20-%20Platinum%20Version%20%28v01%29%20%28U%29.nds";
      hash = "sha256-+85MTe8Md5f43SOKPXpeSLSn46vYaJCsZfYyHO94G9s=";
      name = "pokemon-platinum-usa.nds";
    };
    # Pokemon HeartGold Version (USA), game code IPKE.
    heartgold = fetchIpfs {
      cid = "QmWDWwXu6iQrPpMAfcpGeeb7hc93D2QVhW6cAMjNbSyMC2";
      fallbackUrl = "https://archive.org/download/scxnds_202207/Pokemon%20-%20HeartGold%20Version%20%28v10%29%20%28E%29.nds/4839%20-%20Pokemon%20-%20HeartGold%20Version%20%28v10%29%20%28E%29.nds";
      hash = "sha256-hql3+GPId1n0AB/cRxggkOC/0I9S+n501V23BflrwzU=";
      name = "pokemon-heartgold-usa.nds";
    };
  };

  # config/main.properties seed: registers the baked ROMs so the client
  # skips the rom-panel on launch. Paths are relative to the working dir
  # (the overlay merge root). Filenames match buildScript below.
  romConfig = pkgs.writeText "pokemmo-main.properties" ''
    client.roms.nds=roms/pokemon_black.nds
    client.roms.fr=roms/pokemon_firered.gba
    client.roms.em=roms/pokemon_emerald.gba
    client.roms.nds2=roms/pokemon_platinum.nds
    client.roms.nds3=roms/pokemon_heartgold.nds
  '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "pokemmo";

  ipfsSources = [
    src
    roms.white
    roms.firered
    roms.emerald
    roms.platinum
    roms.heartgold
  ];
  inherit src;

  nativeBuildInputs = [ unzip ];

  buildScript = ''
    mkdir -p "$out/roms" "$out/config"
    unzip -q "$src" -d "$out"

    # Bake the ROMs under roms/ with the exact filenames the client's
    # config keys reference. The client identifies them by header game
    # code; the `pokemon_black.nds` name is the conventional slot for the
    # mandatory Gen-5 ROM (White is accepted there just the same).
    cp "${roms.white}" "$out/roms/pokemon_black.nds"
    cp "${roms.firered}" "$out/roms/pokemon_firered.gba"
    cp "${roms.emerald}" "$out/roms/pokemon_emerald.gba"
    cp "${roms.platinum}" "$out/roms/pokemon_platinum.nds"
    cp "${roms.heartgold}" "$out/roms/pokemon_heartgold.nds"

    # Pre-seed the ROM config so the launcher skips "Locate ROMs".
    cp "${romConfig}" "$out/config/main.properties"
  '';

  # PokeMMO ships a single PokeMMO.exe that is both a Windows launch4j
  # binary and a self-contained fat JAR (LWJGL3 with bundled Linux .so
  # natives extracted via JNI at runtime). PokeMMO.sh just runs
  # `java -cp PokeMMO.exe com.pokeemu.client.Client`, so we do the same
  # with a fresh OpenJDK 17 from nixpkgs and skip the bundled script.
  runtime = "native";

  env = {
    # The JAR-bundled SDL3/GLFW/OpenAL .so files dlopen video/audio
    # backends by bare name; without these on LD_LIBRARY_PATH the JVM
    # crashes during LWJGL init.
    LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        libGL
        libglvnd
        libxkbcommon
        libpulseaudio
        alsa-lib
        dbus
        libdecor
        wayland
        xorg.libX11
        xorg.libXcursor
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXrandr
        xorg.libXScrnSaver
        xorg.libxcb
        stdenv.cc.cc
        zlib
        freetype
        fontconfig
      ]
    );
  };

  runScript = ''
    # ROMs and a seed config/main.properties are baked into the read-only
    # store data and surfaced through the fuse-overlayfs merge root (the
    # working dir = GAMEDIR), so the client registers them at startup and
    # skips the rom-panel ("Locate ROMs") screen.
    #
    # The client rewrites config/main.properties on every save (copy-up
    # into the overlay upper = ~/.strom/pokemmo/), and on a first launch
    # that *predated* this preconfiguration it may already have written a
    # copy with EMPTY client.roms.* values which then shadows the baked
    # seed and re-triggers the rom-panel. Repair that here: ensure the
    # effective config always points the five rom slots at the baked
    # files before the client reads it.
    CFG="$GAMEDIR/config/main.properties"
    mkdir -p "$GAMEDIR/config"
    if [ ! -e "$CFG" ] || ! grep -q '^client\.roms\.nds=roms/pokemon_black\.nds$' "$CFG"; then
      tmp=$(mktemp)
      # Drop any existing client.roms.* lines, then append the correct set.
      grep -v '^client\.roms\.' "$CFG" 2>/dev/null > "$tmp" || true
      {
        echo "client.roms.nds=roms/pokemon_black.nds"
        echo "client.roms.fr=roms/pokemon_firered.gba"
        echo "client.roms.em=roms/pokemon_emerald.gba"
        echo "client.roms.nds2=roms/pokemon_platinum.nds"
        echo "client.roms.nds3=roms/pokemon_heartgold.nds"
      } >> "$tmp"
      mv "$tmp" "$CFG"
    fi
    exec ${lib.getExe pkgs.jdk17} \
      -Xmx384M \
      -Dfile.encoding=UTF-8 \
      -cp PokeMMO.exe com.pokeemu.client.Client "$@"
  '';

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags."--expose-wayland" = true;
  };

  meta = {
    description = "PokeMMO (Java multiplayer Pokemon client; ROMs preconfigured)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "pokemmo";
  };
}
