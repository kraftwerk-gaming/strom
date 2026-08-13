package gaming.kraftwerk.strom.runtime;

/**
 * The runtime apps this client knows how to hand a game to, pinned to
 * exact builds.
 *
 * <p>Pinned rather than "fetch the latest release", because installing
 * one of these makes Strom a distributor of someone else's binary. A
 * floating reference would mean shipping whatever that project published
 * this morning, unreviewed and unverifiable; a hash means the bytes are
 * the ones this client was tested against, and anyone can check them.
 *
 * <p>The table lives in the client rather than in a game's metadata for
 * two reasons: which app can open a game is a property of this client's
 * integration work, not of the game, and putting it in metadata would
 * repeat the same few entries across 464 files. Updating a pin is a
 * client release, which is the honest cadence for "we tested against
 * this version".
 */
final class Runtimes {
    static final class Spec {
        final String pkg;
        final String label;
        final String url;
        /** Lower-case hex sha256 of the APK at {@link #url}. */
        final String sha256;
        final long size;

        Spec(String pkg, String label, String url, String sha256, long size) {
            this.pkg = pkg;
            this.label = label;
            this.url = url;
            this.sha256 = sha256;
            this.size = size;
        }
    }

    /**
     * RetroArch's 64-bit build. The fat APK carries four ABIs and 198 MB;
     * every device this client targets is arm64, so the smaller one is
     * pinned. Note its package differs from the fat build's.
     */
    private static final Spec RETROARCH = new Spec(
        "com.retroarch.aarch64",
        "RetroArch 1.22.2",
        "https://buildbot.libretro.com/stable/1.22.2/android/RetroArch_aarch64.apk",
        "7bd5d208dfe93cc8e2ea6c04608948ce1a045980f160a58ca2d0993aa20ad213",
        183956821L);

    /**
     * WatermelonDS, used for every DS game rather than only on handhelds
     * with two panels. It is a melonDS port and renders both screens on
     * one display just as RetroArch's melonDS core does, so a phone loses
     * nothing; a dual-screen device gains a screen each. One runtime for
     * DS everywhere also means one thing to test and one thing to pin.
     */
    static final Spec WATERMELONDS = new Spec(
        "me.magnum.melondualds",
        "WatermelonDS 0.7.0",
        "https://github.com/SapphireRhodonite/WatermelonDS/releases/download/0.7.0/WatermelonDS-0.7.0.apk",
        "4a370332c97efbf6c36a63461ce9ede9b876516bc977a0ec7e677edaedc919fd",
        27403469L);

    /**
     * Azahar, for 3DS games. The surviving emulator of that console:
     * Citra was deleted after the 2024 Nintendo settlement and Lime3DS
     * merged into Azahar and archived itself in April 2025.
     *
     * <p>The "vanilla" artifact, not "googleplay", and the difference
     * matters to this client rather than being a packaging detail. Only
     * the vanilla build resolves an incoming content:// URI by opening a
     * file descriptor from it; the Play build passes the raw URI on to a
     * path resolver instead. A handoff from here is always a content://
     * URI, because a targetSdk 34 app may not hand another process a
     * file:// one. The two also carry different application ids, so
     * installing the wrong one would leave the game unlaunchable and this
     * client reporting the runtime as missing.
     */
    static final Spec AZAHAR = new Spec(
        "org.azahar_emu.azahar",
        "Azahar 2126.0",
        "https://github.com/azahar-emu/azahar/releases/download/2126.0/azahar-android-vanilla-2126.0.apk",
        "112d354be2145c17fa26d354ba4336445b1549a50bd995140bdeaf7219d5b6ff",
        50206847L);

    private Runtimes() {
    }

    /**
     * The app to offer for a game, or null if we cannot install one.
     *
     * <p>Per game rather than per backend, because a DS game wants a DS
     * emulator even though the manifest routes it through the retroarch
     * backend like every other console.
     */
    static Spec forGame(gaming.kraftwerk.strom.catalog.Game g) {
        if (isNintendoDs(g)) {
            return WATERMELONDS;
        }
        if ("azahar".equals(g.backend)) {
            return AZAHAR;
        }
        if ("retroarch".equals(g.backend)) {
            return RETROARCH;
        }
        // gamenative and dolphin have no verified handoff yet, so there is
        // nothing to install them for.
        return null;
    }

    /** Whether the manifest sends this game to a melonDS-family core. */
    static boolean isNintendoDs(gaming.kraftwerk.strom.catalog.Game g) {
        return g.retroarchCore != null && g.retroarchCore.startsWith("melonds");
    }
}
