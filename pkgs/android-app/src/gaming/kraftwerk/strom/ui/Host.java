package gaming.kraftwerk.strom.ui;

import gaming.kraftwerk.strom.catalog.Game;

import java.util.Map;

/**
 * What the screens ask of the activity.
 *
 * <p>The split is deliberate: everything in this package draws and reads
 * keys, and nothing in it launches a game, touches
 * {@code SharedPreferences} or fetches a catalog. {@code MainActivity}
 * implements this and remains the only caller of {@code Launch.run}, so
 * there is still exactly one launch path shared with
 * {@code LaunchActivity}.
 */
public interface Host {
    /** A game's stored picks, non-default values only. */
    Map<String, String> picks(Game g);

    /** Store a game's picks; only the non-default ones are written. */
    void savePicks(Game g, Map<String, String> picks);

    /** Whether the payload tree is already on the device. */
    boolean downloaded(Game g);

    /** Run the one launch path and report its progress on the game screen. */
    void play(Game g);

    /** Fetch and offer the pinned runtime app for a game's backend. */
    void installRuntime(Game g);

    /** Delete a game's payload so the next Play refetches it with the picks. */
    void resetPayload(Game g);

    /**
     * @param atOptions put the selection on the first option row rather than
     *                  on Play, which is what the options button means
     */
    void openGame(Game g, boolean atOptions);

    void openSettings();

    void backToGrid();

    /** Leave the app, the way BACK does on the grid. */
    void quit();

    String catalogUrl();

    void setCatalogUrl(String url);

    String gateway();

    void setGateway(String url);

    /** Reload the catalog from the stored remote. */
    void reloadCatalog();
}
