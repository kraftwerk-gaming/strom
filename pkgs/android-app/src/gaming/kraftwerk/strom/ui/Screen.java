package gaming.kraftwerk.strom.ui;

/**
 * One full-window view the pad can drive.
 *
 * <p>The app is three of these swapped inside a single activity rather than
 * three activities: the loaded catalog, the decoded cover art and the
 * worker pool are shared, and a launch that hands off to a runtime app has
 * to come back to exactly the screen it left.
 *
 * <p>Every implementor is also a {@code View}; the host casts.
 */
public interface Screen {
    /**
     * @return true when this screen consumed the key, false to let the
     *         platform have it (which is how BACK still leaves the app)
     */
    boolean onPadKey(int code);

    /** A direction from the analog stick, already latched by the host. */
    void onDirection(int dir);

    /**
     * Called every time this screen becomes the visible one, and again when
     * the activity resumes on top of it: what a row says about an installed
     * runtime or a downloaded payload may have changed while another app
     * was in front.
     */
    void onShown();
}
