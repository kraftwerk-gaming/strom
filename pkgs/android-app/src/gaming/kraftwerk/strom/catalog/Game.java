package gaming.kraftwerk.strom.catalog;

/**
 * One catalog entry, flattened from a game's {@code metadata.json}.
 *
 * <p>Almost everything is optional. A game that has never been published
 * for Android carries no {@code android} key at all, which is the common
 * case today and must read as "not playable here" rather than as an error.
 */
public final class Game {
    public String slug;
    public String name;
    public String description;
    public String runtime;

    public String backend;
    public String payloadCid;
    public String payloadName;
    public String payloadSha256;
    public String retroarchCore;
    /** File to open inside the payload: the ROM, or the disc image for Dolphin. */
    public String launchTarget;

    public String executablePath;
    public String execArgs;
    public String screenSize;
    public String dxwrapper;

    /** Backends this client can actually hand off to. */
    public static boolean supported(String backend) {
        return "retroarch".equals(backend)
            || "gamenative".equals(backend)
            || "dolphin".equals(backend);
    }

    /** A game is playable when a runtime can take it and its bytes are published. */
    public boolean isPlayable() {
        return supported(backend) && payloadCid != null && !payloadCid.isEmpty();
    }

    /** What the user sees; falls back to the slug so a row is never blank. */
    public String title() {
        return (name != null && !name.isEmpty()) ? name : slug;
    }

    @Override
    public String toString() {
        return "Game{" + slug
            + " runtime=" + runtime
            + " backend=" + backend
            + " cid=" + payloadCid
            + " playable=" + isPlayable() + "}";
    }
}
