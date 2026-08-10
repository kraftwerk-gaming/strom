# strom probe

A ~12 KB APK that fires the runtime-app handoff intents from a real
application uid. `adb shell am start` runs as uid 2000 (shell), which is
permitted things an ordinary app is not, so it cannot answer whether the
handoff works from our client.

Build (no Gradle; aapt2 + javac + d8 + apksigner from a nix-composed SDK):

    SDK=$(nix build --no-link --print-out-paths --impure --file ~/.claude/outputs/strom-avd/sdk.nix)
    BT=$SDK/libexec/android-sdk/build-tools/34.0.0
    JAR=$SDK/libexec/android-sdk/platforms/android-34/android.jar
    $BT/aapt2 link -I $JAR --manifest AndroidManifest.xml -o build/base.apk
    javac -bootclasspath $JAR -d build/classes $(find src -name '*.java')
    $BT/d8 --lib $JAR --output build $(find build/classes -name '*.class')
    (cd build && cp base.apk probe-unsigned.apk && zip -q -j probe-unsigned.apk classes.dex)
    $BT/zipalign -f 4 build/probe-unsigned.apk build/probe.apk
    $BT/apksigner sign --ks build/debug.keystore --ks-pass pass:android \
        --key-pass pass:android --ks-key-alias probe build/probe.apk

Note `androidenv.composeAndroidPackages` needs
`config.android_sdk.accept_license = true`; without it evaluation fails.

Measured on an x86_64 API 34 AVD, 2026-08-04:

  * intent originates `from uid 10193` (an app), not 2000 (shell)
  * `com.retroarch` visible via the `<queries>` block, with `dataDir` and
    `sourceDir` readable -- so DATADIR/APK extras are computable
  * both `CoreSideloadActivity` and `RetroActivityFuture` resolve
  * the sideload copies the core and Pokemon Blue reaches its title screen

## Where the payload can live (the reason this probe exists)

Measured on a freshly installed client holding no grants at all:

| location | client writes | RetroArch reads |
|---|---|---|
| `/storage/emulated/0/Strom/` | no, needs All-Files | yes |
| `Android/data/<client>/files/` | yes, no permission | **no** |
| internal `getFilesDir()` | yes | no |
| `/storage/emulated/0/Download/Strom/` | **yes, no permission** | **yes** |

The intuitive choice, our own external files dir, fails: RetroArch says
"Input file doesn't exist" for a file the client reads back with
`canRead=true`, because no app may reach into another app's
`Android/data`. Public Downloads is the only spot both processes reach,
and it needs no permission on our side, via direct path or MediaStore.

RetroArch does need its own `READ_EXTERNAL_STORAGE` (revoking it gives
`open failed: EACCES`), but it prompts for that on the same first launch
that creates its `cores/` dir, so both preconditions cost one user step.

Watch out: MediaStore de-duplicates rather than overwrites, so a second
insert of the same name yields `<name> (1).so`. Read `MediaColumns.DATA`
back for the real path, and reuse or delete the previous row.

Run it:

    adb install -r build/probe.apk
    adb shell am start -n gaming.kraftwerk.stromprobe/.ProbeActivity \
        --es via mediastore
    adb logcat -d -s stromprobe:*

Verify a frame without looking at it -- a Game Boy viewport is a 4-colour
image, which is a sharper assertion than eyeballing a screenshot:

    adb exec-out screencap -p > /tmp/f.png
    magick /tmp/f.png -crop 100%x33%+0+100 +repage -format 'colors=%k\n' info:

## Measured, second session (API 34 AVD, 2026-08-05)

Payload location, with the client holding no storage grant at all:

  * `Android/data/<client>/files/` -- client writes fine, RetroArch cannot
    read it. "Input file doesn't exist" for a file whose bytes the client
    reads back itself, md5-identical to the host copy.
  * `/storage/emulated/0/Strom/` -- client cannot even create it without
    All-Files access.
  * `/storage/emulated/0/Download/Strom/` -- works, no permission, by direct
    `File` write or `MediaStore.Downloads`. MediaStore appends " (1)"/" (2)"
    on repeat inserts, so reuse or delete the previous row.

The handoff needs the intent sent TWICE from cold: the first installs the
core and its launch is force-finished, the second runs the game. 2/2 clean
trials. `MANAGE_EXTERNAL_STORAGE` is NOT required -- an earlier reading of
this was wrong, see below.

Two traps that produced wrong intermediate conclusions here:

  * `D sideload: Copying ...` and `Running RetroArch with core ...` are
    logged unconditionally. A run that ends on "Destination directory
    doesn't exist" prints both. Grepping for them as a success signal makes
    a failing configuration look like a passing one, which is what made the
    All-Files grant appear to matter.
  * `chmod` on the FUSE-backed shared storage is silently ignored, and the
    mode you see is synthesised. It is not the access control in play, so
    do not reason from it.
