{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  androidenv,
  jdk17,
  zip,
  # Android refuses to install an update whose versionCode is not greater
  # than the installed one, so a release that does not bump it is a
  # release nobody can receive. Driven from the flake's revCount, which
  # rises with every commit and needs no manual edit.
  versionCode ? 1,
  versionName ? "0.1.0",
}:

# The Strom Android client: fetches a game's payload from IPFS by CID,
# verifies it against the DAG, unpacks it into public shared storage and
# hands off to an installed runtime app (RetroArch today; GameNative and
# Dolphin are the other backends the manifest describes).
#
# Built with aapt2 + javac + d8 + apksigner directly rather than Gradle.
# Gradle wants to resolve dependencies at build time, which a flake cannot
# do offline; this toolchain is already in the composed SDK, needs no
# network, and the app has exactly one third-party dependency, fetched
# below as a fixed-output file and unpacked by hand. That one is
# libarchive, for the tar.zst payload bundles: zstd is not in the platform
# (java.util.zip does deflate and nothing else), so decoding a bundle
# needs native code, and a prebuilt libarchive with zstd linked in is the
# smallest way to get it that does not mean an NDK build of our own.
# That is also why the sources are Java and not Kotlin: no extra compiler
# to pull in, and the whole client is small enough that Kotlin's ergonomics
# do not pay for the added build surface.
#
# Signed with a committed debug keystore so the build is deterministic and
# every machine produces an APK that upgrades in place. This is a debug
# key: it authenticates nothing and is not a secret (Android ships a
# well-known one of its own for exactly this purpose).

let
  sdk =
    (androidenv.composeAndroidPackages {
      platformVersions = [ "34" ];
      buildToolsVersions = [ "34.0.0" ];
      includeEmulator = false;
      includeNDK = false;
      includeSystemImages = false;
    }).androidsdk;

  # libarchive-android (github.com/zhanghai/libarchive-android): libarchive
  # 3.x with zlib, bz2, lzma, lz4, zstd and mbedtls linked in statically,
  # built with ANDROID_STL=none, so the AAR's jni/<abi>/libarchive-jni.so
  # needs only liblog, libm, libdl and libc from the device (readelf -d)
  # and there is no libc++_shared.so to ship beside it. Its Java binding
  # (me.zhanghai.android.libarchive.Archive, ArchiveEntry) is Java 8
  # bytecode in classes.jar. The POM's one dependency, androidx.annotation,
  # is @NonNull/@Nullable with class retention: javac and d8 tolerate the
  # missing annotation types, and nothing looks for them at runtime.
  libarchiveAar = fetchurl {
    url = "https://repo1.maven.org/maven2/me/zhanghai/android/libarchive/library/1.1.6/library-1.1.6.aar";
    hash = "sha256-Btl6N4cqlXTOsr+Uo62Nw4/MiaYPJCQGeyDrXvqmIYk=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "strom-android";
  version = versionName;

  # The manifest carries placeholder values so it stays a valid, buildable
  # file on its own; the real ones are stamped in here.
  postPatch = ''
    substituteInPlace AndroidManifest.xml \
      --replace-fail 'android:versionCode="1"' 'android:versionCode="${toString versionCode}"' \
      --replace-fail 'android:versionName="0.1.0"' 'android:versionName="${versionName}"'
  '';

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./AndroidManifest.xml
      ./debug.keystore
      ./src
      ./test
    ];
  };

  nativeBuildInputs = [
    jdk17
    unzip
    zip
  ];

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"
    SDK=${sdk}/libexec/android-sdk
    BT="$SDK/build-tools/34.0.0"
    JAR="$SDK/platforms/android-34/android.jar"

    mkdir -p build/classes build/aar
    unzip -q ${libarchiveAar} -d build/aar

    # Resource-free app: the UI is built programmatically, so aapt2 only
    # has to compile the manifest into the base APK.
    "$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o build/base.apk

    # -source/-target 8 with android.jar as the bootclasspath is the
    # combination d8 expects; --release is incompatible with -bootclasspath.
    javac -nowarn -source 8 -target 8 -bootclasspath "$JAR" \
      -cp "$JAR:build/aar/classes.jar" \
      -d build/classes $(find src -name '*.java')

    # The binding's classes go into the same dex as ours; d8 takes a jar
    # as an input alongside loose class files.
    "$BT/d8" --lib "$JAR" --output build \
      $(find build/classes -name '*.class') build/aar/classes.jar

    cp build/base.apk build/unsigned.apk

    # zip records each entry's mtime, and classes.dex was just created, so
    # without pinning it the APK differs on every build and a release
    # cannot be checked against the source it claims to come from. -X
    # drops the unix extra fields, which carry a second timestamp. The
    # native libraries get the same treatment: unzip gave them the AAR's
    # own timestamps, which are as arbitrary as "now". They go in as
    # lib/<abi>/, the layout the installer looks in (with
    # extractNativeLibs, see the manifest), every ABI the AAR ships.
    mkdir -p build/lib
    cp -r build/aar/jni/. build/lib/
    touch -d @315532800 build/classes.dex $(find build/lib -type f)
    (cd build && zip -q -X -D unsigned.apk classes.dex $(find lib -type f | sort))

    "$BT/zipalign" -f 4 build/unsigned.apk build/aligned.apk
    "$BT/apksigner" sign \
      --ks debug.keystore --ks-pass pass:android --key-pass pass:android \
      --ks-key-alias strom \
      --out build/strom.apk build/aligned.apk

    runHook postBuild
  '';

  # The verifier is the only thing standing between a hostile gateway and
  # a phone, the layer resolution is the only thing standing between a
  # player's picks and a multi-gigabyte download they did not ask for, and
  # the bundle entry-name rule is the only thing standing between an
  # archive's paths and the directory they may not leave, so all three
  # are tested on every build. These classes touch nothing from
  # android.jar, so they run on the plain JDK with no device or emulator;
  # the tests build tampered CARs and assert each is refused, resolve
  # picks against a manifest and assert the exact layer list and order,
  # and feed hostile entry names to the rule. The libarchive binding is on
  # the classpath because Bundle.java names its classes; nothing here
  # calls into it, so its native library is never loaded.
  doCheck = true;
  checkPhase = ''
    runHook preCheck

    mkdir -p test-classes
    CP=test-classes:build/aar/classes.jar
    # The catalog package is listed file by file because Catalog.java needs
    # android.util.Log, while the option and layer logic it feeds
    # deliberately depends on nothing outside the JDK.
    javac -nowarn -cp "$CP" -d test-classes \
      $(find src/gaming/kraftwerk/strom/ipfs -name '*.java') \
      src/gaming/kraftwerk/strom/catalog/Game.java \
      src/gaming/kraftwerk/strom/catalog/Json.java \
      src/gaming/kraftwerk/strom/catalog/Layer.java \
      src/gaming/kraftwerk/strom/catalog/Options.java \
      src/gaming/kraftwerk/strom/catalog/PadKeys.java \
      src/gaming/kraftwerk/strom/catalog/Setting.java \
      $(find test -name '*.java')
    java -cp "$CP" gaming.kraftwerk.strom.ipfs.CarVerifyTest
    java -cp "$CP" gaming.kraftwerk.strom.ipfs.FetchResumeTest
    java -cp "$CP" gaming.kraftwerk.strom.ipfs.RangedFetchTest
    java -cp "$CP" gaming.kraftwerk.strom.ipfs.BundleTest
    java -cp "$CP" gaming.kraftwerk.strom.catalog.OptionsTest
    java -cp "$CP" gaming.kraftwerk.strom.catalog.PadKeysTest

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp build/strom.apk "$out/strom.apk"
    runHook postInstall
  '';

  meta = {
    description = "Strom Android client: fetches games from IPFS and hands off to an installed runtime";
    platforms = lib.platforms.linux;
  };
}
