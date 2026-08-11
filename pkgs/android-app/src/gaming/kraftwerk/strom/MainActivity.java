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

import gaming.kraftwerk.strom.catalog.Catalog;
import gaming.kraftwerk.strom.catalog.Game;
import gaming.kraftwerk.strom.ipfs.Fetcher;
import gaming.kraftwerk.strom.ipfs.UnixFs;
import gaming.kraftwerk.strom.runtime.CoreInstaller;
import gaming.kraftwerk.strom.runtime.Handoff;
import gaming.kraftwerk.strom.runtime.RuntimeInstaller;

import java.io.File;
import java.util.List;
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

    private ExecutorService pool;
    private LinearLayout list;
    private EditText urlField;
    private EditText filterField;
    private TextView topStatus;
    /** The loaded catalog, kept so the filter can rebuild the list offline. */
    private List<Game> games = java.util.Collections.emptyList();

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
        int shown = 0;
        for (Game g : games) {
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
        int playable = 0;
        for (Game g : games) {
            if (g.isPlayable()) {
                playable++;
            }
        }
        String summary = games.size() + " games, " + playable + " playable"
            + (q.isEmpty() ? "" : ", " + shown + " matching");
        // A catalog where nothing is playable is the expected result when
        // the seed's canonical head predates the revision that published
        // the games, and public seeds do lag. Saying so beats leaving
        // someone to scroll hundreds of greyed-out rows wondering what is
        // broken. A revision pin is deliberately not suggested here: it is
        // a testing affordance, and the normal answer is another seed.
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
        final boolean installed = Handoff.available(this, g.backend);
        final String offer = RuntimeInstaller.offerLabel(g.backend);

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
            status.setText(human(RuntimeInstaller.offerSize(g.backend))
                + " download, then Play");
        } else if (!installed) {
            play.setText("runtime app not installed");
            status.setText("nothing pinned for backend '" + g.backend + "'");
        } else {
            play.setText("Play");
        }
        play.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                play.setEnabled(false);
                // Re-check rather than trusting what the row was built
                // with: the user may have installed it since, from here or
                // from anywhere else.
                if (!Handoff.available(MainActivity.this, g.backend)) {
                    installRuntime(g, status, play);
                } else {
                    prepareAndLaunch(g, status, play);
                }
            }
        });
        box.addView(play);
        return box;
    }

    /** Fetch and offer the pinned runtime app for a game's backend. */
    private void installRuntime(final Game g, final TextView status, final Button play) {
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    say(status, "fetching " + RuntimeInstaller.offerLabel(g.backend));
                    RuntimeInstaller.install(MainActivity.this, g.backend,
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

    private void prepareAndLaunch(final Game g, final TextView status, final Button play) {
        pool.submit(new Runnable() {
            @Override
            public void run() {
                try {
                    if ("retroarch".equals(g.backend)) {
                        say(status, "fetching core " + g.retroarchCore);
                        CoreInstaller.ensure(g.retroarchCore);
                    }

                    File dir = CoreInstaller.payloadDir(g.slug);
                    if (!present(dir)) {
                        // A single-file payload extracts to a file and a
                        // directory payload to a tree, and which one it is
                        // is only known once the DAG arrives. Land it on a
                        // scratch path, then put it where it belongs.
                        File part = new File(dir.getAbsolutePath() + ".part");
                        say(status, "fetching payload");
                        UnixFs.Stats st = Fetcher.fetchAndExtract(
                            g.payloadCid, part, new Fetcher.Progress() {
                                @Override
                                public void bytes(long soFar) {
                                    say(status, "fetching " + human(soFar));
                                }
                            });
                        place(part, dir, g);
                        say(status, "verified " + st.blocks + " blocks, "
                            + human(st.bytesOut));
                    } else {
                        say(status, "already downloaded");
                    }

                    say(status, "handing off");
                    Handoff.launch(MainActivity.this, g, dir);
                    say(status, "launched");
                } catch (final Exception e) {
                    // Surfaced on screen, not just logcat: this gets
                    // debugged over adb on a phone and a silent failure
                    // costs an hour.
                    Log.w(TAG, "launch failed for " + g.slug, e);
                    say(status, "failed: " + e);
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

    private static boolean present(File dir) {
        if (dir.isFile()) {
            return dir.length() > 0;
        }
        String[] kids = dir.list();
        return kids != null && kids.length > 0;
    }

    /**
     * Move a freshly fetched payload into place. A file payload is given
     * its published name inside the game's directory so the extension
     * survives; a directory payload becomes the directory itself.
     */
    private static void place(File part, File dir, Game g) throws java.io.IOException {
        if (part.isDirectory()) {
            if (!part.renameTo(dir)) {
                throw new java.io.IOException("cannot move " + part + " to " + dir);
            }
            return;
        }
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new java.io.IOException("cannot create " + dir);
        }
        String name = (g.payloadName != null && !g.payloadName.isEmpty())
            ? g.payloadName : g.slug;
        File dst = new File(dir, name);
        if (!part.renameTo(dst)) {
            throw new java.io.IOException("cannot move " + part + " to " + dst);
        }
    }

    private void say(final TextView t, final String s) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                t.setText(s);
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
