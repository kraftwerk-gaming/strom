# games/balatro/apk.nix
#
# Build a signed Balatro Android APK by running the `balatromobile` tool
# (./balatromobile) inside a pure, offline derivation. balatromobile
# bundles everything it needs (APKEditor, the LÖVE 11.5 SAF embed APK,
# zipalign, uber-apk-signer, a debug keystore), so this build needs no
# network and no Android SDK.
#
# Why this instead of hand-patching: injecting the raw Game.love into the
# stock LÖVE embed APK boots to a black screen because Balatro's CRT
# shader does not render on most Android GPUs. balatromobile applies the
# community patch set -- crucially `no-crt` (the black-screen fix), plus
# `basic` (touch input + mobile flags), `landscape`, and an FPS cap -- to
# the game's Lua before packaging. The patches are version-gated; our
# Balatro is 1.0.1o-FULL, which balatromobile's `basic` patch supports.
#
# We feed it the clean Game.love (a zip of the game's Lua + assets with
# main.lua and version.jkr at the root). balatromobile reads it as a zip
# -- the same way it reads the fused Balatro.exe -- so a .love works as
# the input just as well as the .exe, and lets us reuse the Game.love we
# already extract in ./default.nix (loveSrc).
#
# This is plugged into the game's android submodule as
# `android.outputs.apk` (see ./default.nix), so the generic
# lib/android proton/Wine builder stays untouched.

{
  lib,
  stdenvNoCC,
  balatromobile,

  # Directory containing the .love, and its filename within (loveSrc).
  gameData,
  loveMainFile ? "Game.love",

  gameName ? "balatro",
  appId ? "gaming.kraftwerk.strom.balatro",
  displayName ? "balatro",
  versionName ? "1.0.0",

  # Comma-separated balatromobile patch list. Defaults to the upstream
  # DEFAULT_PATCHES set (which includes `no-crt`).
  patches ? "basic,landscape,no-crt,fps,external-storage,shaders-flames,fix-beta-langs,max-volume",
}:

stdenvNoCC.mkDerivation {
  pname = "strom-${gameName}-apk";
  version = versionName;

  dontUnpack = true;

  nativeBuildInputs = [ balatromobile ];

  buildPhase = ''
    runHook preBuild

    # APKEditor/java want a writable HOME for their caches.
    export HOME="$TMPDIR"
    mkdir -p "$out"

    balatromobile android "${gameData}/${loveMainFile}" \
      --output "$out/${gameName}.apk" \
      --patches "${patches}" \
      --package-name "${appId}" \
      --display-name "${displayName}"

    test -f "$out/${gameName}.apk" \
      || (echo "balatromobile produced no APK" >&2; exit 1)

    runHook postBuild
  '';

  dontInstall = true;

  meta = {
    description = "Balatro Android APK built via balatromobile (CRT shader disabled)";
    # Host-build platform; the artifact targets aarch64-android.
    platforms = lib.platforms.linux;
  };
}
