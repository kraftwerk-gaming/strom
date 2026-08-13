package gaming.kraftwerk.strom.catalog;

import java.util.Collections;
import java.util.List;

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
    /**
     * File to open inside the payload: the ROM, the disc image for
     * Dolphin, or the 3DS dump for Azahar.
     */
    public String launchTarget;

    public String executablePath;
    public String execArgs;
    public String screenSize;
    public String dxwrapper;

    /**
     * The game's published player options, empty when it has none.
     *
     * <p>Exactly {@code passthru.settingsSchema}, so this client and the
     * desktop couch launcher offer the same rows for the same game.
     */
    public List<Setting> settings = Collections.emptyList();
    /**
     * Optional mod trees, in extraction order, empty when the game has none.
     *
     * <p>Each is fetched only when the player's picks select it and unpacked
     * over the base payload, so a moddable game is one pinned base plus one
     * pinned tree per mod rather than one payload per combination.
     */
    public List<Layer> layers = Collections.emptyList();

    /** Backends this client can actually hand off to. */
    public static boolean supported(String backend) {
        return "retroarch".equals(backend)
            || "azahar".equals(backend)
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
