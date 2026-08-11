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
     * WatermelonDS, for DS games on handhelds with two physical panels.
     * Offered only where it would actually be used, which the caller
     * decides; installing a DS emulator on a phone helps nobody.
     */
    static final Spec WATERMELONDS = new Spec(
        "me.magnum.melondualds",
        "WatermelonDS 0.7.0",
        "https://github.com/SapphireRhodonite/WatermelonDS/releases/download/0.7.0/WatermelonDS-0.7.0.apk",
        "4a370332c97efbf6c36a63461ce9ede9b876516bc977a0ec7e677edaedc919fd",
        27403469L);

    private Runtimes() {
    }

    /** The app to offer for a backend, or null if we cannot install one. */
    static Spec forBackend(String backend) {
        if ("retroarch".equals(backend)) {
            return RETROARCH;
        }
        // gamenative and dolphin have no verified handoff yet, so there is
        // nothing to install them for.
        return null;
    }
}
