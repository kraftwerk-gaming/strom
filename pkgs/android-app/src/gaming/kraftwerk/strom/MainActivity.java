package gaming.kraftwerk.strom;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.text.InputType;
import android.util.Log;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import gaming.kraftwerk.strom.catalog.Catalog;
import gaming.kraftwerk.strom.catalog.Game;
import gaming.kraftwerk.strom.catalog.Layer;
import gaming.kraftwerk.strom.catalog.Options;
import gaming.kraftwerk.strom.catalog.Setting;
import gaming.kraftwerk.strom.ipfs.Fetcher;
import gaming.kraftwerk.strom.ipfs.UnixFs;
import gaming.kraftwerk.strom.runtime.CoreInstaller;
import gaming.kraftwerk.strom.runtime.Handoff;
import gaming.kraftwerk.strom.runtime.RuntimeInstaller;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * The whole client: point it at a catalog, pick a game, and it fetches the
 * payload by CID, verifies it against the DAG and hands off to a runtime.
 *
 * <p>Built entirely in code. The APK carries no resources, which keeps the
 * build to aapt2-plus-javac-plus-d8 with no Gradle and no AndroidX.
 */
public class MainActivity extends Activity {
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
     * and can sit well behind master, in which case nothing in the
     * catalog is installable -- the status line says so rather than
     * leaving it to be guessed at, and the remote field exists to point
     * somewhere fresher, optionally pinning a revision with
     * {@code #<commit>}.
     */
    private static final String DEFAULT_CATALOG =
        "https://ash.radicle.garden/api/v1/repos/rad:zaCSBVa8UbKNEWBcmRTW1m9fZXhu";

    private static final String PREFS = "strom";
    private static final String PREF_CATALOG = "catalog-url";
    private static final String PREF_GATEWAY = "private-gateway";
    /** One entry per game that has options, holding just its non-default picks. */
    private static final String PREF_OPTIONS = "options:";
    /**
     * Which mod layers are unpacked into a game directory.
     *
     * <p>Kept inside the tree it describes, so deleting the game forgets it
     * too and the two can never disagree.
     */
    private static final String LAYER_MARKER = ".strom-layers";

    private ExecutorService pool;
    private LinearLayout list;
    private EditText urlField;
    private EditText gatewayField;
    private EditText filterField;
    private TextView topStatus;
    /** The loaded catalog, kept so the filter can rebuild the list offline. */
    private List<Game> games = java.util.Collections.emptyList();
    /**
     * Whether to list games this device cannot run. Off by default: most of
     * the catalog is PC titles with no Android payload, so leaving them in
     * buries the handful that do run under hundreds of dead rows.
     */
    private boolean showAll;
    private Button showAllToggle;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        pool = Executors.newFixedThreadPool(2);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(12);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Strom");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        root.addView(title);

        TextView remoteLabel = new TextView(this);
        remoteLabel.setText("Remote");
        remoteLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        remoteLabel.setTextColor(Color.GRAY);
        root.addView(remoteLabel);

        urlField = new EditText(this);
        urlField.setInputType(InputType.TYPE_TEXT_VARIATION_URI);
        urlField.setSingleLine(true);
        urlField.setHint("radicle seed, or an http server serving /games");
        // Remembered across launches. A seed URL carries a base32 RID and
        // optionally a commit sha, which is not something to retype on a
        // phone keyboard every time the app is opened.
        urlField.setText(getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(PREF_CATALOG, DEFAULT_CATALOG));
        root.addView(urlField);

        Button load = new Button(this);
        load.setText("Load catalog");
        load.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                String url = urlField.getText().toString().trim();
                getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit().putString(PREF_CATALOG, url).apply();
                loadCatalog(url);
            }
        });
        root.addView(load);

        // Same idea as STROM_IPFS_GATEWAYS on the desktop (AGENTS.md): a
        // private or LAN mirror is tried first and the public gateways stay
        // as the fallback. Safe to point anywhere, because the CID is the
        // only trusted input -- a gateway that answers with the wrong bytes
        // fails DAG verification and the next one gets a turn.
        TextView gatewayLabel = new TextView(this);
        gatewayLabel.setText("Private gateway (optional)");
        gatewayLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        gatewayLabel.setTextColor(Color.GRAY);
        root.addView(gatewayLabel);

        gatewayField = new EditText(this);
        gatewayField.setInputType(InputType.TYPE_TEXT_VARIATION_URI);
        gatewayField.setSingleLine(true);
        gatewayField.setHint("http://host:8080");
        gatewayField.setText(getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(PREF_GATEWAY, ""));
        gatewayField.addTextChangedListener(new android.text.TextWatcher() {
            @Override
            public void afterTextChanged(android.text.Editable e) {
                String g = e.toString().trim();
                getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit().putString(PREF_GATEWAY, g).apply();
                Fetcher.setPrivateGateway(g);
            }

            @Override
            public void beforeTextChanged(CharSequence s, int a, int b, int c) {
            }

            @Override
            public void onTextChanged(CharSequence s, int a, int b, int c) {
            }
        });
        root.addView(gatewayField);
        Fetcher.setPrivateGateway(gatewayField.getText().toString().trim());

        topStatus = new TextView(this);
        topStatus.setText("idle");
        root.addView(topStatus);

        // 464 games do not browse in a flat scroll on a handheld.
        filterField = new EditText(this);
        filterField.setSingleLine(true);
        filterField.setHint("filter");
        filterField.addTextChangedListener(new android.text.TextWatcher() {
            @Override
            public void afterTextChanged(android.text.Editable e) {
                render();
            }

            @Override
            public void beforeTextChanged(CharSequence s, int a, int b2, int c) {
            }

            @Override
            public void onTextChanged(CharSequence s, int a, int b2, int c) {
            }
        });
        root.addView(filterField);

        showAllToggle = new Button(this);
        showAllToggle.setText("Show all games");
        showAllToggle.setEnabled(false);
        showAllToggle.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showAll = !showAll;
                render();
            }
        });
        root.addView(showAllToggle);

        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(list, new ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll);

        setContentView(root);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        pool.shutdownNow();
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private void loadCatalog(final String base) {
        topStatus.setText("loading " + base);
        list.removeAllViews();
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    final List<Game> loaded = Catalog.load(base);
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            games = loaded;
                            render();
                        }
                    });
                } catch (final Exception e) {
                    Log.w(TAG, "catalog load failed", e);
                    showTop("catalog failed: " + e);
                }
            }
        });
    }

    /** Rebuild the visible rows from the loaded catalog and the filter. */
    private void render() {
        String q = filterField.getText().toString().trim().toLowerCase();
        list.removeAllViews();
        int playable = 0;
        for (Game g : games) {
            if (g.isPlayable()) {
                playable++;
            }
        }
        int hidden = showAll ? 0 : games.size() - playable;

        int shown = 0;
        for (Game g : games) {
            if (!showAll && !g.isPlayable()) {
                continue;
            }
            if (!q.isEmpty()
                && !g.title().toLowerCase().contains(q)
                && !g.slug.toLowerCase().contains(q)) {
                continue;
            }
            // Cap the rendered rows: every row is a handful of views, and
            // inflating 464 of them janks the UI thread for no benefit when
            // the user is going to filter anyway.
            if (shown >= 60) {
                TextView more = new TextView(this);
                more.setText("... filter to narrow down");
                list.addView(more);
                break;
            }
            list.addView(row(g));
            shown++;
        }

        showAllToggle.setText(showAll
            ? "Show only what runs here"
            : "Show all " + games.size() + " games");
        showAllToggle.setEnabled(games.size() > playable || showAll);

        String summary = playable + " playable"
            + (hidden > 0 ? ", " + hidden + " not published for Android" : "")
            + (q.isEmpty() ? "" : ", " + shown + " matching");
        // A catalog where nothing is playable is the expected result when
        // the seed's canonical head predates the revision that published
        // the games, and public seeds do lag. Saying so beats leaving
        // someone with an empty list wondering what is broken. A revision
        // pin is deliberately not suggested here: it is a testing
        // affordance, and the normal answer is another seed.
        if (!games.isEmpty() && playable == 0) {
            summary += "\nNo game here is published for Android yet."
                + " This seed's master may predate them; try another remote.";
        }
        topStatus.setText(summary);
    }

    private void showTop(final String s) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                topStatus.setText(s);
            }
        });
    }

    /** One game: title, subtitle, a play button and its own status line. */
    private View row(final Game g) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(0, dp(8), 0, dp(8));

        TextView name = new TextView(this);
        name.setText(g.title());
        name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        box.addView(name);

        TextView sub = new TextView(this);
        sub.setText("runtime " + g.runtime + "   backend " + g.backend);
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        sub.setTextColor(Color.GRAY);
        box.addView(sub);

        final TextView status = new TextView(this);
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        box.addView(status);

        final Button play = new Button(this);
        final boolean installed = Handoff.available(this, g);
        final String offer = RuntimeInstaller.offerLabel(g);

        play.setEnabled(g.isPlayable() && (installed || offer != null));
        if (!g.isPlayable()) {
            play.setText("not published for Android");
            status.setText(g.payloadCid == null
                ? "no payload CID in metadata.json"
                : "backend '" + g.backend + "' unsupported");
        } else if (!installed && offer != null) {
            // The runtime is missing but we have a pinned build of it, so
            // offer that rather than telling someone to go and find an APK.
            play.setText("Install " + offer);
            status.setText(human(RuntimeInstaller.offerSize(g))
                + " download, then Play");
        } else if (!installed) {
            play.setText("runtime app not installed");
            status.setText("nothing pinned for backend '" + g.backend + "'");
        } else {
            play.setText("Play");
        }

        // Turning a mod back off cannot be done by unpacking anything, so
        // the only honest answer is to fetch the game again -- and the base
        // is gigabytes, so that is offered on a button the player has to
        // press, shown only once a pick actually needs it.
        final Button reset = new Button(this);
        reset.setText("Delete this download and start over");
        reset.setVisibility(View.GONE);
        reset.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                reset.setEnabled(false);
                pool.submit(new Runnable() {
                    @Override
                    public void run() {
                        say(status, "deleting");
                        Fetcher.deleteTree(CoreInstaller.payloadDir(g));
                        say(status, "deleted; press Play to download it with your options");
                        runOnUiThread(new Runnable() {
                            @Override
                            public void run() {
                                reset.setEnabled(true);
                                reset.setVisibility(View.GONE);
                            }
                        });
                    }
                });
            }
        });

        play.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                play.setEnabled(false);
                // Re-check rather than trusting what the row was built
                // with: the user may have installed it since, from here or
                // from anywhere else.
                if (!Handoff.available(MainActivity.this, g)) {
                    installRuntime(g, status, play);
                } else {
                    prepareAndLaunch(g, status, play, reset);
                }
            }
        });
        box.addView(play);

        // Only games that publish options get the affordance; for the rest
        // there is nothing behind it.
        if (!g.settings.isEmpty()) {
            final LinearLayout panel = new LinearLayout(this);
            panel.setOrientation(LinearLayout.VERTICAL);
            panel.setPadding(dp(12), 0, 0, 0);
            panel.setVisibility(View.GONE);

            final Button show = new Button(this);
            show.setText("Options");
            show.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    boolean open = panel.getVisibility() == View.VISIBLE;
                    show.setText(open ? "Options" : "Hide options");
                    panel.setVisibility(open ? View.GONE : View.VISIBLE);
                    if (!open) {
                        buildOptions(g, panel, reset);
                    }
                }
            });
            box.addView(show);
            box.addView(panel);
        }
        box.addView(reset);
        return box;
    }

    /**
     * The options panel: one row per published setting, a bool toggling and
     * an enum cycling its choices.
     *
     * <p>Rebuilt after every pick rather than mutated in place, because a
     * pick changes what its neighbours may offer: a parent switch going off
     * takes the option that depends on it with it.
     */
    private void buildOptions(final Game g, final LinearLayout panel, final Button reset) {
        panel.removeAllViews();
        final Map<String, String> picks = picks(g);

        for (final Setting s : g.settings) {
            final String off = Options.unavailable(g, s, picks);
            final String current = Options.value(s, picks);

            final Button b = new Button(this);
            b.setText(s.title() + ": " + current);
            // A pick that could not be honoured must not be pickable at all;
            // the line underneath says which reason it is.
            b.setEnabled(off == null);
            b.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    List<String> usable = Options.selectable(g, s, picks);
                    int at = usable.indexOf(current);
                    picks.put(s.key, usable.get((at + 1) % usable.size()));
                    savePicks(g, picks);
                    // Whatever the picks were when the offer to delete this
                    // download appeared, they have just changed; Play works
                    // out again whether it is still the only way forward.
                    reset.setVisibility(View.GONE);
                    buildOptions(g, panel, reset);
                }
            });
            panel.addView(b);

            TextView note = new TextView(this);
            note.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
            note.setTextColor(Color.GRAY);
            note.setText(off != null ? off : detail(g, s, current, picks));
            panel.addView(note);
        }

        // Counted, not just summed: a manifest may publish a layer without a
        // size, and "no mods selected" would then be a lie about a download
        // that is about to happen.
        List<Layer> chosen = Options.select(g, picks);
        long extra = Options.bytes(chosen);
        TextView total = new TextView(this);
        total.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        total.setTextColor(Color.GRAY);
        total.setText(chosen.isEmpty()
            ? "no mods selected"
            : chosen.size() + " mod layer(s) selected"
                + (extra > 0 ? ", " + human(extra) + " to download" : ""));
        panel.addView(total);
    }

    /** An offered row's second line: what the option does, and what it costs. */
    private static String detail(Game g, Setting s, String current, Map<String, String> picks) {
        String help = (s.help == null) ? "" : s.help;
        long size = Options.bytes(Options.wouldSelect(g, s, current, picks));
        return size > 0 ? help + "  (+" + human(size) + ")" : help;
    }

    /** A game's stored picks; only the non-default ones are ever written. */
    private Map<String, String> picks(Game g) {
        return Options.decode(getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(PREF_OPTIONS + g.slug, ""));
    }

    private void savePicks(Game g, Map<String, String> picks) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putString(PREF_OPTIONS + g.slug, Options.encode(g.settings, picks))
            .apply();
    }

    /** Fetch and offer the pinned runtime app for a game's backend. */
    private void installRuntime(final Game g, final TextView status, final Button play) {
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    say(status, "fetching " + RuntimeInstaller.offerLabel(g));
                    RuntimeInstaller.install(MainActivity.this, g,
                        new RuntimeInstaller.Progress() {
                            @Override
                            public void bytes(long soFar, long total) {
                                say(status, "fetching runtime " + human(soFar)
                                    + (total > 0 ? " of " + human(total) : ""));
                            }
                        });
                    say(status, "confirm the install, then press Play");
                } catch (final Exception e) {
                    Log.w(TAG, "runtime install failed for " + g.slug, e);
                    say(status, "install failed: " + e);
                } finally {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            play.setEnabled(true);
                            play.setText("Play");
                        }
                    });
                }
            }
        });
    }

    private void prepareAndLaunch(final Game g, final TextView status, final Button play,
        final Button reset) {
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    Launch.Outcome out = Launch.run(MainActivity.this, g, picks(g),
                        new Launch.Progress() {
                            @Override
                            public void say(String message) {
                                MainActivity.this.say(status, message);
                            }
                        });
                    say(status, out.message);
                    if (out.result == Launch.Result.NEEDS_SETUP
                        || out.result == Launch.Result.REFUSED) {
                        // A row of our own UI cannot be read once the runtime
                        // we just opened is covering us, which is how this
                        // presents as "I pressed Play and nothing happened".
                        toast(out.message);
                    }
                    if (out.staleLayers) {
                        show(reset);
                    }
                } finally {
                    // Including after a launch that worked. Quitting the game
                    // returns the player here, and the obvious thing to do
                    // next is play it again; a button that stays dead until
                    // the list happens to be rebuilt is just a dead button.
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            play.setEnabled(true);
                        }
                    });
                }
            }
        });
    }

    private void show(final View v) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                v.setVisibility(View.VISIBLE);
            }
        });
    }

    private void say(final TextView t, final String s) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                t.setText(s);
            }
        });
    }

    /** Said where it can still be read once another app is in front. */
    private void toast(final String s) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                Toast.makeText(MainActivity.this, s, Toast.LENGTH_LONG).show();
            }
        });
    }

    private static String human(long n) {
        if (n < 1024) {
            return n + " B";
        }
        if (n < 1024 * 1024) {
            return String.format("%.1f KiB", n / 1024.0);
        }
        if (n < 1024L * 1024 * 1024) {
            return String.format("%.1f MiB", n / (1024.0 * 1024));
        }
        return String.format("%.2f GiB", n / (1024.0 * 1024 * 1024));
    }
}
