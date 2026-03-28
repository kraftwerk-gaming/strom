{
  fetchurl,
  fetchFromGitHub,
  lib,
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
  writeShellScript,
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

  gameFiles = fetchurl {
    url = "https://archive.org/download/die_siedler_2_151/siedler2.zip";
    hash = "sha256-9FUecyRKFygEaoppZ+welasCe9HZHMG1y0BKwZpt0nw=";
    name = "settlers2-gold.zip";
  };

  gameDataExtracted =
    runCommandLocal "settlers2-data"
      {
        nativeBuildInputs = [ unzip ];
      }
      ''
        mkdir -p "$out"
        unzip -o ${gameFiles} -d "$out/"
      '';

  # Combined prefix with s25client + game data in S2/
  combinedPrefix = runCommandLocal "settlers2-prefix" { } ''
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
    ln -sfn "${gameDataExtracted}/DATA" "$out/share/s25rttr/S2/DATA"
    ln -sfn "${gameDataExtracted}/GFX" "$out/share/s25rttr/S2/GFX"

    # Symlink bin and lib
    ln -s ${s25client}/bin/* $out/bin/
    ln -s ${s25client}/lib/* $out/lib/
  '';

  wrapper = writeShellScript "settlers2" ''
    mkdir -p "''${HOME:-.}/.strom/settlers2"
    ln -sfn "''${HOME:-.}/.strom/settlers2" "''${HOME:-.}/.s25rttr"
    export RTTR_PREFIX_DIR="${combinedPrefix}"
    exec ${lib.getExe s25client} "$@"
  '';

in
stdenv.mkDerivation {
  pname = "settlers2";
  inherit version;

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    ln -s ${wrapper} $out/bin/settlers2
  '';

  meta = {
    description = "The Settlers II Gold (via Return to the Roots)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "settlers2";
  };
}
