{
  cmake,
  fetchFromGitHub,
  fetchurl,
  libpng,
  libavif,
  libjpeg,
  libjxl,
  libtiff,
  libwebp,
  ninja,
  p7zip,
  pkg-config,
  python3,
  unar,
  runCommandLocal,
  SDL2,
  SDL2_image,
  SDL2_mixer,
  stdenv,
  gamescope,
  writeShellApplication,
  cli11,
  crcpp,
  utf8cpp,
}:

let
  libADLMIDI-src = fetchFromGitHub {
    owner = "Wohlstand";
    repo = "libADLMIDI";
    rev = "2b350f9ef5fa7bafd90b8ce3beb2a77c1e87af25";
    hash = "sha256-kN7vwH+CxJAYo2I/6mub3vOesFHB6SunKZJ10PHsbzU=";
  };

  freesynd = stdenv.mkDerivation {
    pname = "freesynd";
    version = "0.959";

    src = fetchFromGitHub {
      owner = "bni";
      repo = "freesynd";
      rev = "fa27909aa576df22cdb2044eb63f5c2293d57be2";
      hash = "sha256-sEDwVqsbGcC+0lMACOvflArN+Rlx/RASWa2TqGHbCyY=";
    };

    nativeBuildInputs = [
      cmake
      ninja
      pkg-config
      python3
    ];

    buildInputs = [
      SDL2
      SDL2_image
      SDL2_mixer
      libpng
      libtiff
      libwebp
      libavif
      libjpeg
      libjxl
      cli11
      crcpp
      utf8cpp
    ];

    postPatch = ''
      # Create cmake config for CRCpp (header-only, nixpkgs has no cmake config)
      mkdir -p cmake/CRCpp
      cat > cmake/CRCpp/CRCppConfig.cmake << CMAKE
      add_library(crcpp::crcpp INTERFACE IMPORTED)
      set_target_properties(crcpp::crcpp PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${crcpp}/include"
      )
      CMAKE

      # Fix utf8cpp target name: nixpkgs provides utf8cpp::utf8cpp,
      # but freesynd links against plain "utf8cpp"
      find . -name CMakeLists.txt -exec sed -i \
        's/target_link_libraries(\(.*\) utf8cpp)/target_link_libraries(\1 utf8cpp::utf8cpp)/g' {} +

      # Remove project's FindSDL2*.cmake so cmake uses system SDL2 configs
      rm -f cmake/FindSDL2.cmake cmake/FindSDL2_image.cmake cmake/FindSDL2_mixer.cmake

      # Fix SDL2 target names for nixpkgs compatibility
      sed -i 's/SDL2::Main/SDL2::SDL2/g' engine/CMakeLists.txt
      sed -i 's/SDL2::Image/SDL2_image::SDL2_image/g' engine/CMakeLists.txt
      sed -i 's/SDL2::Mixer/SDL2_mixer::SDL2_mixer/g' engine/CMakeLists.txt

      # Fix case-sensitive found variable names (config mode vs module mode)
      sed -i 's/SDL2_IMAGE_FOUND/SDL2_image_FOUND/g' engine/CMakeLists.txt

      # Skip CRC validation of original data (allows Syndicate Plus files)
      sed -i 's/if (!fs_utl::File::testOriginalData())/if (false)/' engine/src/base_app.cpp

      # Fix crash in PanicComponent::execute - dangling pArmedPed_ pointer.
      # The cached pArmedPed_ can point to freed memory when a ped is destroyed.
      # Fix: always re-lookup via findNearbyArmedPed instead of caching.
      python3 ${./fix-panic-crash.py} kernel/src/ia/behaviour.cpp
    '';

    hardeningDisable = [ "format" ];

    env.NIX_CFLAGS_COMPILE = "-Wno-error";

    postInstall = ''
      rm -rf $out/lib/pkgconfig
    '';

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DUSE_SYSTEM_SDL=ON"
      "-DUSE_SDL_MIXER=ON"
      "-DBUILD_TESTING=OFF"
      "-DFETCHCONTENT_SOURCE_DIR_LIBADL=${libADLMIDI-src}"
      "-DCRCpp_DIR=${placeholder "out"}/../build/cmake/CRCpp"
    ];

    preConfigure = ''
      export CRCpp_DIR=$PWD/cmake/CRCpp
    '';
  };

  # BR archive has correct GAME/SOUND/MAP/sprite files (verified CRCs)
  gameArchiveBR = fetchurl {
    url = "https://archive.org/download/syndicate-1993_202412/Freesynd.rar";
    hash = "sha256-q5vhyv6ShZi5w3xRYBrbrC4BUJ+RycV3L7rgO1KvGG0=";
    name = "syndicate-freesynd.rar";
  };

  # Syndicate Plus CD has English mission briefings (MISS*.DAT)
  gameArchiveCD = fetchurl {
    url = "https://archive.org/download/syndicate-plus-1994-ea-bullfrog-ms-dos-cd/Syndicate.Plus.1994.EA.Bullfrog.MS-DOS.CD.7z";
    hash = "sha256-8RC+DzBzm+mCnXw08GLlS6/659h2mX/dMB8GfXbnvfA=";
    name = "syndicate-plus.7z";
  };

  gameData =
    runCommandLocal "syndicate-data"
      {
        nativeBuildInputs = [
          p7zip
          python3
          unar
        ];
      }
      ''
        mkdir -p $out/work

        # Extract BR archive (correct game/sound/map data)
        unar -o "$out/work" ${gameArchiveBR}
        cp -r "$out/work"/*/data "$out/data"

        # Extract Syndicate Plus CD for English MISS files
        7z x ${gameArchiveCD} -o"$out/work/cd"
        MDF=$(find "$out/work/cd" -iname "new.mdf" | head -1)
        python3 -c "
        import os
        mdf = '$MDF'
        iso = '$out/work/syndicate.iso'
        SECTOR_SIZE = 2448
        DATA_OFFSET = 16
        DATA_SIZE = 2048
        with open(mdf, 'rb') as f_in, open(iso, 'wb') as f_out:
            total = os.path.getsize(mdf)
            for i in range(total // SECTOR_SIZE):
                f_in.seek(i * SECTOR_SIZE + DATA_OFFSET)
                f_out.write(f_in.read(DATA_SIZE))
        "
        7z x "$out/work/syndicate.iso" -o"$out/work/iso"

        # Overwrite MISS files with English versions from CD
        for f in "$out/work/iso/SYNDICAT/DATA"/MISS*.DAT; do
          base=$(basename "$f")
          cp "$f" "$out/data/$base"
        done

        # Clean up work directory
        rm -rf "$out/work"

        # Convert filenames to lowercase as required by FreeSynd
        cd "$out"
        find . -depth -name '*[A-Z]*' | while read f; do
          dir=$(dirname "$f")
          base=$(basename "$f")
          lower=$(echo "$base" | tr 'A-Z' 'a-z')
          if [ "$base" != "$lower" ]; then
            mv "$dir/$base" "$dir/$lower"
          fi
        done
      '';
in
writeShellApplication {
  name = "syndicate";
  runtimeInputs = [ gamescope ];
  text = ''
    GAMEDIR="''${HOME:-.}/.strom/syndicate"
    mkdir -p "$GAMEDIR"

    # Create config if not exists
    if [ ! -f "$GAMEDIR/freesynd.ini" ]; then
      cat > "$GAMEDIR/freesynd.ini" << EOF
    freesynd_data_dir = ${freesynd}/share/freesynd
    data_dir = ${gameData}/data
    time_for_click = 80
    EOF
    fi

    cd "$GAMEDIR"
    # Force windowed mode in user.conf
    if [ -f "$GAMEDIR/user.conf" ]; then
      sed -i 's/fullscreen = true/fullscreen = false/' "$GAMEDIR/user.conf"
    fi

    exec gamescope -W 1920 -H 1080 -w 1920 -h 1080 -- \
      ${freesynd}/bin/freesynd -i "$GAMEDIR" -u "$GAMEDIR"
  '';
}
