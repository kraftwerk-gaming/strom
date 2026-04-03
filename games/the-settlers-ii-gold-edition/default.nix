{
  self,
  fetchIpfs,
  fetchFromGitHub,
  lib,
  pkgs,
  cmake,
  boost,
  SDL2,
  SDL2_mixer,
  curl,
  bzip2,
  gettext,
  lua5_3,
  miniupnpc,
  libsamplerate,
  runCommandLocal,
  stdenv,
  unzip,
}:

let

  version = "unstable-2025-03-17";
  rev = "e4146df452217e8e0ddb62c6a5482008f80c3153";

  s25client = stdenv.mkDerivation {
    pname = "s25client";
    inherit version;

    src = fetchFromGitHub {
      owner = "Return-To-The-Roots";
      repo = "s25client";
      inherit rev;
      hash = "sha256-hJo+mxwBfvH2JDAn4bERm5NJ9ZuIGW+K9XeVOGl7yFU=";
      fetchSubmodules = true;
    };

    nativeBuildInputs = [
      cmake
      gettext
    ];

    buildInputs = [
      boost
      SDL2
      SDL2_mixer
      curl
      bzip2
      lua5_3
      miniupnpc
      libsamplerate
    ];

    postPatch = ''
      # boost_system is header-only in modern Boost; remove explicit requests
      sed -i 's/system filesystem iostreams/filesystem iostreams/g' external/libsiedler2/CMakeLists.txt || true
      sed -i 's/system program_options/program_options/g' external/libsiedler2/examples/lstpacker/CMakeLists.txt || true

      # Fix missing #include <cstdint> for newer GCC
      sed -i '1i #include <cstdint>' external/libsiedler2/src/oem.cpp || true
      if [ -f external/kaguya/include/kaguya/native_function.hpp ]; then
        sed -i '/#include/a #include <cstdint>' external/kaguya/include/kaguya/native_function.hpp
      fi

      # Fix miniupnpc API change (added ipv6 parameter)
      sed -i 's/UPNP_GetValidIGD(deviceList, \&urls, \&data, \&lanAddr\[0\], lanAddr.size())/UPNP_GetValidIGD(deviceList, \&urls, \&data, \&lanAddr[0], lanAddr.size(), nullptr, 0)/g' \
        external/libutil/libs/network/src/UPnP_Other.cpp || true
    '';

    env.NIX_CFLAGS_COMPILE = "-Wno-error";

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DRTTR_VERSION=0.10.0"
      "-DRTTR_REVISION=0000000000000000000000000000000000000000"
      "-DRTTR_USE_SYSTEM_LIBS=ON"
      "-DBUILD_TESTING=OFF"
      "-DRTTR_BUILD_UPDATER=OFF"
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
    ];

    meta = {
      description = "Return to the Roots - Settlers II remake";
      homepage = "https://www.rttr.info";
      license = lib.licenses.gpl2Plus;
      platforms = [ "x86_64-linux" ];
      mainProgram = "s25client";
    };
  };

  gameFilesArchive = fetchIpfs {
    cid = "QmNoB7Qgf3yR9vjin1bVCUkdajG8nTsdd8mF2SamXXT6vM";
    fallbackUrl = "https://archive.org/download/die_siedler_2_151/siedler2.zip";
    hash = "sha256-9FUecyRKFygEaoppZ+welasCe9HZHMG1y0BKwZpt0nw=";
    name = "the-settlers-ii-gold-edition.zip";
    };

  # Combined prefix: s25client + game data in S2/
  combinedPrefix =
    runCommandLocal "the-settlers-ii-gold-edition-prefix"
      {
        nativeBuildInputs = [ unzip ];
      }
      ''
        mkdir -p $out/share/s25rttr/S2 $out/bin $out/lib

        # Symlink s25client's share tree (except S2)
        for f in ${s25client}/share/s25rttr/*; do
          name="$(basename "$f")"
          [ "$name" = "S2" ] && continue
          ln -s "$f" "$out/share/s25rttr/$name"
        done

        # Symlink S2 contents from s25client, then overlay game data
        for f in ${s25client}/share/s25rttr/S2/*; do
          ln -s "$f" "$out/share/s25rttr/S2/$(basename "$f")"
        done

        # Extract and add original game data
        unzip -o ${gameFilesArchive} -d /tmp/s2data
        rm -f "$out/share/s25rttr/S2/DATA" "$out/share/s25rttr/S2/GFX"
        cp -r /tmp/s2data/DATA "$out/share/s25rttr/S2/DATA"
        cp -r /tmp/s2data/GFX "$out/share/s25rttr/S2/GFX"

        # Symlink bin and lib
        ln -s ${s25client}/bin/* $out/bin/
        ln -s ${s25client}/lib/* $out/lib/
      '';
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "the-settlers-ii-gold-edition";

  # s25rttr uses its own prefix, not a flat game dir.
  # We use a dummy src and point RTTR_PREFIX_DIR at the combined prefix.
  src = combinedPrefix;
  buildScript = ''
    mkdir -p "$out"
    echo "the-settlers-ii-gold-edition" > "$out/.placeholder"
  '';

  runtime = "native";

  runScript = ''
    # s25rttr stores config in ~/.s25rttr, point it at our game dir
    ln -sfn "$GAMEDIR" "$HOME/.s25rttr"
    export RTTR_PREFIX_DIR="${combinedPrefix}"

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 --expose-wayland -- \
      ${lib.getExe s25client}
  '';

  meta = {
    description = "The Settlers II Gold (via Return to the Roots)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "the-settlers-ii-gold-edition";
  };
}
