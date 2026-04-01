{
  stdenv,
  fetchurl,
  cmake,
  pkg-config,
  wayland-scanner,
  libpulseaudio,
  alsa-lib,
  systemd,
  libGL,
  vulkan-loader,
  libx11,
  libxext,
  libxrandr,
  libxi,
  libxcursor,
  libxinerama,
  libxcb,
  libxfixes,
  libxkbcommon,
  wayland,
  wayland-protocols,
  libdecor,
  dbus,
}:

stdenv.mkDerivation {
  pname = "sdl2";
  version = "2.30.12";

  src = fetchurl {
    url = "https://github.com/libsdl-org/SDL/releases/download/release-2.30.12/SDL2-2.30.12.tar.gz";
    hash = "sha256-rDVupV6LndCy0fon2kDvfiOCZ8z5MkcEhQ1dRzdbSOo=";
  };

  outputs = [
    "out"
    "dev"
  ];

  nativeBuildInputs = [
    cmake
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    libpulseaudio
    alsa-lib
    systemd
    libGL
    vulkan-loader
    libx11
    libxext
    libxrandr
    libxi
    libxcursor
    libxinerama
    libxcb
    libxfixes
    libxkbcommon
    wayland
    wayland-protocols
    libdecor
    dbus
  ];

  cmakeFlags = [
    "-DSDL_SHARED=ON"
    "-DSDL_STATIC=OFF"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
  ];

  postFixup = "rm -f $out/lib/cmake/SDL2/sdl2-config.cmake";
  dontFixCmake = true;
}
