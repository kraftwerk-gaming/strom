package gaming.kraftwerk.strom;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.Toast;

import gaming.kraftwerk.strom.catalog.Catalog;
import gaming.kraftwerk.strom.catalog.Game;
import gaming.kraftwerk.strom.catalog.Options;
import gaming.kraftwerk.strom.ipfs.Fetcher;
import gaming.kraftwerk.strom.runtime.CoreInstaller;
import gaming.kraftwerk.strom.runtime.RuntimeInstaller;
import gaming.kraftwerk.strom.ui.CoverCache;
import gaming.kraftwerk.strom.ui.GameGrid;
import gaming.kraftwerk.strom.ui.GameScreen;
import gaming.kraftwerk.strom.ui.Host;
import gaming.kraftwerk.strom.ui.Keys;
import gaming.kraftwerk.strom.ui.Screen;
import gaming.kraftwerk.strom.ui.SettingsScreen;
import gaming.kraftwerk.strom.ui.Theme;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The couch UI: a grid of cover art, a screen per game, and the app's own
 * settings behind a shoulder button.
 *
 * <p>Shaped after the desktop couch launcher ({@code pkgs/launcher}), for
 * the same reason it exists: this runs on a handheld with a physical pad and
 * two panels, held at arm's length, and a column of text fields and buttons
 * is not something a thumb can drive. The pad is the primary input and touch
 * keeps working.
 *
 * <p>This class is the host, not a view: it owns the worker pool, the
 * preferences, the catalog and the one call to {@link Launch#run}, and the
 * screens in {@code ui/} draw and read keys. Keeping the launch here means
 * the automation entry point ({@link LaunchActivity}) and a player pressing
 * Play still go down the identical path.
 *
 * <p>Built entirely in code. The APK carries no resources, which keeps the
 * build to aapt2-plus-javac-plus-d8 with no Gradle and no AndroidX.
 */
public class MainActivity extends Activity implements Host {
    private static final String TAG = "strom";

    /**
     * The remote the catalog is read from, unless the user names another.
     *
     * <p>A public Radicle seed carrying this repo, so a fresh install has
     * somewhere real to point at. It once defaulted to an emulator's host
     * loopback, which was useless on a phone twice over: nothing listens
     * there, and the manifest forbids cleartext.
     *
     * <p>Any seed that carries the repo works, and so does a plain HTTP
     * server exposing {@code /games/}. Seeds fetch on their own schedule
     * and can sit well behind master, in which case nothing in the catalog
     * is installable -- the grid's status line says so rather than leaving
     * it to be guessed at, and the settings screen's remote field exists to
     * point somewhere fresher, optionally pinning a revision with
     * {@code #<commit>}.
     */
    static final String DEFAULT_CATALOG =
        "https://ash.radicle.garden/api/v1/repos/rad:zaCSBVa8UbKNEWBcmRTW1m9fZXhu";

    private static final String PREFS = "strom";
    private static final String PREF_CATALOG = "catalog-url";
    private static final String PREF_GATEWAY = "private-gateway";
    /** One entry per game that has options, holding just its non-default picks. */
    private static final String PREF_OPTIONS = "options:";

    /** A held stick moves once, then repeats, like a held d-pad does. */
    private static final int REPEAT_DELAY_MS = 350;
    private static final int REPEAT_MS = 90;
    private static final float STICK_ON = 0.6f;
    private static final float STICK_OFF = 0.3f;

    /**
     * The loaded catalog, for the life of the process.
     *
     * <p>Static on purpose: reading it is one HTTP request per game and
     * there are hundreds of them, while this activity is destroyed and
     * recreated by anything from a rotation to moving the window to the
     * device's second panel. Immutable data, so sharing it is free.
     */
    private static List<Game> catalog = Collections.emptyList();
    private static String catalogFrom;

    private ExecutorService pool;
    private CoverCache covers;
    private GameGrid grid;
    private GameScreen gameScreen;
    private SettingsScreen settingsScreen;
    private Screen active;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private Runnable repeater;
    private int latchX;
    private int latchY;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        // Two: one for a catalog load or a payload fetch, one left over so a
        // reset or a runtime install is not stuck behind it. Cover art has
        // its own pool inside CoverCache.
        pool = Executors.newFixedThreadPool(2);
        covers = new CoverCache(this);

        Theme theme = new Theme(this);
        FrameLayout root = new FrameLayout(this);
        root.setBackground(Theme.background());

        grid = new GameGrid(this, theme, this, covers);
        gameScreen = new GameScreen(this, theme, this, covers);
        settingsScreen = new SettingsScreen(this, theme, this, covers);
        for (View v : new View[] { grid, gameScreen, settingsScreen }) {
            root.addView(v, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
            v.setVisibility(View.GONE);
        }
        setContentView(root);
        show(grid);

        Fetcher.setPrivateGateway(gateway());

        String url = catalogUrl();
        if (!catalog.isEmpty() && url.equals(catalogFrom)) {
            grid.setGames(catalog);
        } else {
            // Loaded without being asked. The old screen made "Load catalog"
            // the first thing a player had to find, and there is nothing
            // else this app could usefully be doing on startup.
            reloadCatalog();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Coming back from a runtime app, the package installer, or a game:
        // what the rows say about installed runtimes and downloaded payloads
        // may no longer be true.
        if (active != null) {
            active.onShown();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopRepeat();
        pool.shutdownNow();
        covers.shutdown();
    }

    // ---- input -----------------------------------------------------------

    /**
     * All key handling for all three screens.
     *
     * <p>{@code dispatchKeyEvent} rather than {@code onKeyDown}: the
     * activity sees the event before the view tree, which is what lets the
     * grid own the d-pad without every tile being a focusable view, and it
     * keeps one mapping for pad buttons, a bluetooth keyboard and
     * {@code adb shell input keyevent} alike.
     *
     * <p>The one place the view tree wins is text entry. A field is only
     * focusable while it is being edited (see {@code Theme.startEditing}),
     * so a focused {@link EditText} means the player is typing: characters
     * go to it, and the buttons that mean "done" end the edit rather than
     * reaching the screen underneath.
     */
    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        if (e.getAction() != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(e);
        }
        int code = e.getKeyCode();
        View focused = getCurrentFocus();
        if (focused instanceof EditText) {
            if (Keys.back(code) || Keys.commit(code)) {
                Theme.stopEditing((EditText) focused);
                return true;
            }
            return super.dispatchKeyEvent(e);
        }
        if (active != null && active.onPadKey(code)) {
            return true;
        }
        return super.dispatchKeyEvent(e);
    }

    /**
     * The left stick, as a direction.
     *
     * <p>A pad's hat switch arrives as {@code KEYCODE_DPAD_*} and needs
     * nothing here, but a stick is an axis: it has to be latched (fire once
     * per crossing of the threshold, re-arm below a lower one) and repeated
     * by hand, because there is no key-repeat behind it. Both thresholds
     * and both timings are the desktop launcher's.
     */
    @Override
    public boolean onGenericMotionEvent(MotionEvent e) {
        boolean stick = (e.getSource() & InputDevice.SOURCE_JOYSTICK)
            == InputDevice.SOURCE_JOYSTICK;
        if (!stick || e.getAction() != MotionEvent.ACTION_MOVE || active == null) {
            return super.onGenericMotionEvent(e);
        }
        latchX = latch(latchX, axis(e, MotionEvent.AXIS_X, MotionEvent.AXIS_HAT_X),
            Keys.LEFT, Keys.RIGHT);
        latchY = latch(latchY, axis(e, MotionEvent.AXIS_Y, MotionEvent.AXIS_HAT_Y),
            Keys.UP, Keys.DOWN);
        return true;
    }

    /** The stronger of a stick axis and the hat that shares its direction. */
    private static float axis(MotionEvent e, int stickAxis, int hatAxis) {
        float s = e.getAxisValue(stickAxis);
        float h = e.getAxisValue(hatAxis);
        return Math.abs(h) > Math.abs(s) ? h : s;
    }

    private int latch(int prev, float v, int negative, int positive) {
        if (Math.abs(v) > STICK_ON) {
            int now = v > 0 ? 1 : -1;
            if (prev != now) {
                int dir = now > 0 ? positive : negative;
                active.onDirection(dir);
                startRepeat(dir);
            }
            return now;
        }
        if (Math.abs(v) < STICK_OFF) {
            if (prev != 0) {
                stopRepeat();
            }
            return 0;
        }
        return prev;
    }

    private void startRepeat(final int dir) {
        stopRepeat();
        repeater = new Runnable() {
            @Override
            public void run() {
                if (active != null) {
                    active.onDirection(dir);
                }
                ui.postDelayed(this, REPEAT_MS);
            }
        };
        ui.postDelayed(repeater, REPEAT_DELAY_MS);
    }

    private void stopRepeat() {
        if (repeater != null) {
            ui.removeCallbacks(repeater);
            repeater = null;
        }
    }

    // ---- navigation ------------------------------------------------------

    private void show(Screen s) {
        stopRepeat();
        View focused = getCurrentFocus();
        if (focused instanceof EditText) {
            Theme.stopEditing((EditText) focused);
        }
        if (active != null) {
            ((View) active).setVisibility(View.GONE);
        }
        active = s;
        ((View) s).setVisibility(View.VISIBLE);
        s.onShown();
    }

    @Override
    public void openGame(Game g, boolean atOptions) {
        gameScreen.setGame(g, atOptions);
        show(gameScreen);
    }

    @Override
    public void openSettings() {
        show(settingsScreen);
    }

    @Override
    public void backToGrid() {
        show(grid);
    }

    @Override
    public void quit() {
        finish();
    }

    // ---- preferences -----------------------------------------------------

    @Override
    public String catalogUrl() {
        return getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(PREF_CATALOG, DEFAULT_CATALOG);
    }

    @Override
    public void setCatalogUrl(String url) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(PREF_CATALOG, url).apply();
    }

    @Override
    public String gateway() {
        return getSharedPreferences(PREFS, MODE_PRIVATE).getString(PREF_GATEWAY, "");
    }

    @Override
    public void setGateway(String url) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(PREF_GATEWAY, url).apply();
        Fetcher.setPrivateGateway(url);
    }

    /** A game's stored picks; only the non-default ones are ever written. */
    @Override
    public Map<String, String> picks(Game g) {
        return Options.decode(getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(PREF_OPTIONS + g.slug, ""));
    }

    @Override
    public void savePicks(Game g, Map<String, String> picks) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(PREF_OPTIONS + g.slug, Options.encode(g.settings, picks))
            .apply();
    }

    // ---- work ------------------------------------------------------------

    @Override
    public boolean downloaded(Game g) {
        return Launch.present(CoreInstaller.payloadDir(g));
    }

    @Override
    public void reloadCatalog() {
        final String base = catalogUrl();
        grid.setStatus("loading " + base);
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    final List<Game> loaded = Catalog.load(base);
                    ui.post(new Runnable() {
                        @Override
                        public void run() {
                            catalog = loaded;
                            catalogFrom = base;
                            grid.setGames(loaded);
                        }
                    });
                } catch (final Exception e) {
                    Log.w(TAG, "catalog load failed", e);
                    ui.post(new Runnable() {
                        @Override
                        public void run() {
                            grid.setStatus("catalog failed: " + e);
                        }
                    });
                }
            }
        });
    }

    @Override
    public void play(final Game g) {
        gameScreen.setBusy(true);
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    Launch.Outcome out = Launch.run(MainActivity.this, g, picks(g),
                        new Launch.Progress() {
                            @Override
                            public void say(String message) {
                                MainActivity.this.say(g, message);
                            }
                        });
                    say(g, out.message);
                    if (out.result == Launch.Result.NEEDS_SETUP
                        || out.result == Launch.Result.REFUSED) {
                        // Our own screen cannot be read once the runtime we
                        // just opened is covering us, which is how this
                        // presents as "I pressed Play and nothing happened".
                        toast(out.message);
                    }
                    if (out.staleLayers) {
                        offerReset(g);
                    }
                } finally {
                    // Including after a launch that worked. Quitting the game
                    // returns the player here, and the obvious thing to do
                    // next is play it again.
                    ui.post(new Runnable() {
                        @Override
                        public void run() {
                            gameScreen.setBusy(false);
                        }
                    });
                }
            }
        });
    }

    /** Fetch and offer the pinned runtime app for a game's backend. */
    @Override
    public void installRuntime(final Game g) {
        gameScreen.setBusy(true);
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    say(g, "fetching " + RuntimeInstaller.offerLabel(g));
                    RuntimeInstaller.install(MainActivity.this, g,
                        new RuntimeInstaller.Progress() {
                            @Override
                            public void bytes(long soFar, long total) {
                                say(g, "fetching runtime " + Launch.human(soFar)
                                    + (total > 0 ? " of " + Launch.human(total) : ""));
                            }
                        });
                    say(g, "confirm the install, then press Play");
                } catch (final Exception e) {
                    Log.w(TAG, "runtime install failed for " + g.slug, e);
                    say(g, "install failed: " + e);
                } finally {
                    ui.post(new Runnable() {
                        @Override
                        public void run() {
                            gameScreen.setBusy(false);
                        }
                    });
                }
            }
        });
    }

    @Override
    public void resetPayload(final Game g) {
        gameScreen.setBusy(true);
        pool.submit(new Runnable() {
            @Override
            public void run() {
                say(g, "deleting");
                Fetcher.deleteTree(CoreInstaller.payloadDir(g));
                say(g, "deleted; press Play to download it with your options");
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        gameScreen.offerReset(false);
                        gameScreen.setBusy(false);
                    }
                });
            }
        });
    }

    // ---- talking back ----------------------------------------------------

    /**
     * Show a worker's message on the game's screen, if that is still the
     * game on screen: a launch keeps running while the player walks back to
     * the grid, and its progress must not be written over another game.
     */
    private void say(final Game g, final String s) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                if (gameScreen.game() == g) {
                    gameScreen.say(s);
                }
            }
        });
    }

    private void offerReset(final Game g) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                if (gameScreen.game() == g) {
                    gameScreen.offerReset(true);
                }
            }
        });
    }

    /** Said where it can still be read once another app is in front. */
    private void toast(final String s) {
        ui.post(new Runnable() {
            @Override
            public void run() {
                Toast.makeText(MainActivity.this, s, Toast.LENGTH_LONG).show();
            }
        });
    }
}
