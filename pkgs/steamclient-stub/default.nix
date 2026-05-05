{
  lib,
  stdenv,
  pkgsi686Linux,
}:

let
  buildLib =
    buildStdenv:
    buildStdenv.mkDerivation {
      pname = "steamclient-stub-${buildStdenv.hostPlatform.system}";
      version = "0";
      src = ./.;
      buildPhase = ''
        runHook preBuild
        $CXX -shared -fPIC -nostdlib++ -fno-rtti -fno-exceptions -Wall -Wextra -O2 \
          -o steamclient.so steamclient.cpp
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        install -Dm0644 steamclient.so $out/steamclient.so
        runHook postInstall
      '';
    };

  lib32 = buildLib pkgsi686Linux.stdenv;
  lib64 = buildLib stdenv;
in
stdenv.mkDerivation {
  pname = "steamclient-stub";
  version = "0";
  dontUnpack = true;
  installPhase = ''
    install -Dm0644 ${lib32}/steamclient.so $out/sdk32/steamclient.so
    install -Dm0644 ${lib64}/steamclient.so $out/sdk64/steamclient.so
  '';
  meta = with lib; {
    description = "Minimal steamclient.so stub so Proton runs without a host Steam install";
    platforms = [ "x86_64-linux" ];
  };
}
