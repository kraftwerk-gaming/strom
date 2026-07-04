# games/balatro/balatromobile/default.nix
#
# balatromobile (https://github.com/antipatico/balatromobile): a *NIX-
# friendly Python rewrite of balatro-mobile-maker that converts a Steam
# Balatro into an Android APK. Unlike the original it downloads nothing
# at runtime -- it bundles APKEditor, the official LÖVE 11.5 SAF embed
# APK, a statically-linked Go `zipalign`, uber-apk-signer and a debug
# keystore as package data. The only runtime deps are Python 3.11+ and a
# JRE (it shells out to `java` for APKEditor + the signer).
#
# Balatro-specific, so it lives here under games/balatro rather than in
# the generic pkgs/ tree. We use it to apply the community's well-tested
# mobile patch set to Balatro's .love -- most importantly `no-crt`, which
# removes the CRT shader that renders a black screen on many Android
# GPUs. See ../apk.nix for the APK build itself.
#
# Packaged from the prebuilt PyPI wheel: it carries the bundled binaries
# (the git repo keeps them in LFS, so fetchFromGitHub would only get
# pointers). The wheel is pure data + Python, so there is nothing to
# compile.

{
  lib,
  python3,
  fetchurl,
  jdk17,
  makeWrapper,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "balatromobile";
  version = "0.6.4";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/8e/28/07d9e3caa9a4abbe75909897ec58c71a914e4f586ec2901a7681b57d437b/balatromobile-${version}-py3-none-any.whl";
    hash = "sha256-1rIDvQAJ/UCzJRgLA7qjN3uGARJBvpkAFJrRLHxFAhA=";
  };

  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3.pkgs.tabulate ];

  # The bundled per-OS zipalign binaries lose their executable bit going
  # through the wheel install, but balatromobile execs them by path. The
  # Linux one is a static Go build (no interpreter/libs), so once it is
  # +x it runs as-is on NixOS. The unguarded glob makes a future layout
  # change fail the build here instead of at APK-build time. Also put a
  # JDK on PATH for the `java` invocations (APKEditor decode/build +
  # apksigner).
  postInstall = ''
    chmod +x "$out/${python3.sitePackages}/balatromobile/artifacts/zipalign-"*
    wrapProgram "$out/bin/balatromobile" \
      --prefix PATH : ${lib.makeBinPath [ jdk17 ]}
  '';

  pythonImportsCheck = [ "balatromobile" ];

  meta = {
    description = "Convert a Steam Balatro into an Android APK (bundles APKEditor + LÖVE embed)";
    homepage = "https://github.com/antipatico/balatromobile";
    mainProgram = "balatromobile";
    platforms = lib.platforms.linux;
  };
}
