package gaming.kraftwerk.strom.catalog;

import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Builds the game list by reading each game's per-game files directly.
 *
 * <p>There is no {@code catalog.json} in the repo, on purpose: a shared
 * index would make every concurrent game addition a merge conflict. The
 * cost is one request per game, which is why these are fetched in
 * parallel. This mirrors what the web GUI ({@code web/gui/app.js}) already
 * does in the browser, and speaks the same two protocols it does.
 */
public final class Catalog {
    private static final String TAG = "strom";
    private static final String UA = "strom-android/0.1";
    private static final int PARALLEL = 8;
    private static final int TIMEOUT_MS = 20000;

    private Catalog() {
    }

    /**
     * @param baseUrl either a Radicle {@code <api>/repos/<rid>} URL, or the
     *                root of a plain static server exposing {@code /games/}.
     *
     *                <p>The normal form carries no revision, and the
     *                catalog is then read at the project's canonical head,
     *                which is that mirror's current master. A revision is
     *                never required.
     *
     *                <p>One may be appended as {@code ...#<commit-sha>} to
     *                read the repo at a specific commit, which exists to
     *                test an unmerged branch on a device before it lands.
     *                It has to be a commit id rather than a branch name:
     *                radicle-httpd resolves tree and blob paths by oid, and
     *                a contributor's branches live under
     *                {@code refs/namespaces/<did>/...}, where a bare name
     *                does not resolve.
     *
     *                <p>Following the canonical head rather than the newest
     *                head any delegate happens to have published is
     *                deliberate. Delegates disagree: ash currently reports
     *                three different master heads for this repo. The
     *                canonical one is the threshold-signed state, and
     *                "newest" is not even well defined without the commit
     *                graph, which a client that has cloned nothing does not
     *                have.
     */
    public static List<Game> load(String baseUrl) throws IOException {
        String base = baseUrl.trim();
        String pinned = null;
        int hash = base.indexOf('#');
        if (hash >= 0) {
            pinned = base.substring(hash + 1).trim();
            base = base.substring(0, hash);
        }
        if (base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }
        boolean radicle = base.contains("/api/v1");

        String head = null;
        if (radicle) {
            head = (pinned != null && !pinned.isEmpty()) ? pinned : radicleHead(base);
            Log.i(TAG, "catalog at " + base + " rev " + head
                + (pinned != null ? " (pinned)" : " (canonical head)"));
        }
        List<String> slugs = radicle ? radicleSlugs(base, head) : staticSlugs(base);
        if (slugs.isEmpty()) {
            throw new IOException("no games found under " + base);
        }

        final String fbase = base;
        final String fhead = head;
        final boolean frad = radicle;

        ExecutorService pool = Executors.newFixedThreadPool(PARALLEL);
        List<Game> out = new ArrayList<Game>();
        try {
            List<Future<Game>> futures = new ArrayList<Future<Game>>(slugs.size());
            for (final String slug : slugs) {
                futures.add(pool.submit(new Callable<Game>() {
                    @Override
                    public Game call() {
                        try {
                            return one(fbase, fhead, frad, slug);
                        } catch (Exception e) {
                            // One unreadable game must not sink the catalog.
                            Log.w(TAG, "skipping " + slug + ": " + e);
                            return null;
                        }
                    }
                }));
            }
            for (Future<Game> f : futures) {
                try {
                    Game g = f.get();
                    if (g != null) {
                        out.add(g);
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    throw new IOException("interrupted while loading the catalog", e);
                } catch (ExecutionException e) {
                    Log.w(TAG, "catalog entry failed", e);
                }
            }
        } finally {
            pool.shutdownNow();
        }

        Collections.sort(out, new Comparator<Game>() {
            @Override
            public int compare(Game a, Game b) {
                return a.title().compareToIgnoreCase(b.title());
            }
        });
        return out;
    }

    /** The manifest omits a key when it equals the documented default. */
    private static String orElse(String v, String fallback) {
        return (v == null || v.isEmpty()) ? fallback : v;
    }

    private static Game one(String base, String head, boolean radicle, String slug)
        throws IOException {
        Object m = fetchJson(base, head, radicle, slug, "metadata.json");

        Game g = new Game();
        g.slug = slug;
        g.name = Json.str(m, "name");
        g.description = Json.str(m, "description");
        g.runtime = Json.str(m, "runtime");

        // The `android` key is the manifest that lib/android/default.nix
        // projects, so the shape here is the schema documented in
        // docs/android.md: the launch details sit under a per-backend
        // object rather than being flattened.
        g.backend = Json.str(m, "android", "backend");
        g.payloadCid = Json.str(m, "android", "payload", "cid");
        g.payloadName = Json.str(m, "android", "payload", "name");
        g.payloadSha256 = Json.str(m, "android", "payload", "sha256");

        g.retroarchCore = Json.str(m, "android", "retroarch", "core");
        if ("dolphin".equals(g.backend)) {
            g.launchTarget = Json.str(m, "android", "dolphin", "disc");
        } else if ("azahar".equals(g.backend)) {
            g.launchTarget = Json.str(m, "android", "azahar", "rom");
        } else {
            g.launchTarget = Json.str(m, "android", "retroarch", "rom");
        }

        g.executablePath =
            Json.str(m, "android", "gamenative", "containerConfig", "executablePath");
        // The manifest omits these when they equal the default, because
        // they are identical across all 269 gamenative entries and would
        // otherwise be ~15 KB of repetition in the catalog. Absent means
        // default; the pair of defaults is documented in docs/android.md
        // alongside the ones lib/android/default.nix filters against.
        g.execArgs = orElse(Json.str(m, "android", "gamenative", "containerConfig", "execArgs"), "");
        g.screenSize =
            orElse(Json.str(m, "android", "gamenative", "containerConfig", "screenSize"), "1280x720");
        g.dxwrapper =
            orElse(Json.str(m, "android", "gamenative", "containerConfig", "dxwrapper"), "dxvk");

        // steam.json supplies the display name for most games; metadata.json
        // wins where it sets one, which is the same precedence the web GUI
        // and the couch launcher apply.
        if (g.name == null) {
            try {
                Object s = fetchJson(base, head, radicle, slug, "steam.json");
                g.name = Json.str(s, "name");
                if (g.description == null) {
                    g.description = Json.str(s, "short");
                }
            } catch (IOException e) {
                // Off-Steam titles legitimately have no steam.json.
                Log.d(TAG, slug + ": no steam.json");
            }
        }
        return g;
    }

    /**
     * Read one of a game's JSON files.
     *
     * <p>The two sources differ in shape, not just in URL: a plain server
     * returns the file, while radicle-httpd's blob route wraps it in an
     * envelope and puts the file in a {@code content} string. The web GUI
     * does the same unwrapping.
     */
    private static Object fetchJson(String base, String head, boolean radicle,
        String slug, String file) throws IOException {
        if (!radicle) {
            return Json.parse(getString(base + "/games/" + slug + "/" + file));
        }
        Object envelope = Json.parse(
            getString(base + "/blob/" + head + "/games/" + slug + "/" + file));
        String content = Json.str(envelope, "content");
        if (content == null) {
            throw new IOException("radicle blob carried no content: " + slug + "/" + file);
        }
        return Json.parse(content);
    }

    // ---- radicle-httpd ---------------------------------------------------

    private static String radicleHead(String base) throws IOException {
        Object repo = Json.parse(getString(base));
        Object head = Json.path(repo, "payloads", "xyz.radicle.project", "meta", "head");
        if (!(head instanceof String)) {
            throw new IOException("no project head at " + base);
        }
        return (String) head;
    }

    private static List<String> radicleSlugs(String base, String head) throws IOException {
        Object tree = Json.parse(getString(base + "/tree/" + head + "/games"));
        Object entries = Json.path(tree, "entries");
        List<String> slugs = new ArrayList<String>();
        if (entries instanceof List) {
            for (Object e : (List<?>) entries) {
                if (e instanceof Map && "tree".equals(Json.str(e, "kind"))) {
                    String n = Json.str(e, "name");
                    if (n != null) {
                        slugs.add(n);
                    }
                }
            }
        }
        return slugs;
    }

    // ---- plain static server ---------------------------------------------

    /** Scrape a directory listing for {@code <a href="<slug>/">} entries. */
    private static final Pattern HREF_DIR =
        Pattern.compile("href=\"([^\"/?#][^\"?#]*)/\"", Pattern.CASE_INSENSITIVE);

    private static List<String> staticSlugs(String base) throws IOException {
        String html = getString(base + "/games/");
        List<String> slugs = new ArrayList<String>();
        Matcher m = HREF_DIR.matcher(html);
        while (m.find()) {
            String name = m.group(1);
            if (name.equals("..") || name.equals(".")) {
                continue;
            }
            slugs.add(name);
        }
        return slugs;
    }

    // ---- http ------------------------------------------------------------

    private static String getString(String url) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try {
            c.setRequestProperty("User-Agent", UA);
            c.setRequestProperty("Accept", "*/*");
            c.setConnectTimeout(TIMEOUT_MS);
            c.setReadTimeout(TIMEOUT_MS);
            int code = c.getResponseCode();
            if (code != 200) {
                throw new IOException("HTTP " + code + " for " + url);
            }
            InputStream in = c.getInputStream();
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) {
                bo.write(buf, 0, n);
            }
            return bo.toString("UTF-8");
        } finally {
            c.disconnect();
        }
    }
}
