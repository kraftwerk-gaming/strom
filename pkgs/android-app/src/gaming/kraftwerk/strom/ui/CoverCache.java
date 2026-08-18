package gaming.kraftwerk.strom.ui;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.LruCache;
import android.widget.ImageView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.Map;
import java.util.WeakHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Cover art for the grid: fetched lazily, decoded off the UI thread, cached
 * in memory and on disk at the size a tile actually needs.
 *
 * <p>Three properties this has to have, all learned the hard way:
 *
 * <ul>
 *   <li><b>Nothing is prefetched.</b> The catalog is hundreds of games and
 *       their art is over a gigabyte of JPEG; a player who opens the app on
 *       a phone link must not pay for the art of games they never scroll
 *       past. Art is requested per visible tile and abandoned when that
 *       tile is recycled to another game.
 *   <li><b>Decoding is bounded.</b> A Steam hero decodes to megabytes, and
 *       hundreds of them at full size is an OOM, not a slow app. So the
 *       bounds are read first ({@code inJustDecodeBounds}), the decode is
 *       subsampled to roughly tile size, and the result is cropped to
 *       exactly tile size before anything caches it.
 *   <li><b>The disk cache is the real cache.</b> It stores the cropped,
 *       tile-sized JPEG keyed by a hash of the URL, so a second run of the
 *       app draws the grid from ~30 KB files with no network at all, and a
 *       memory cache that was evicted costs a decode rather than a
 *       download.
 * </ul>
 *
 * <p>Lives in {@code getCacheDir()/covers}: art is derived data, and the
 * platform may delete a cache dir under storage pressure without breaking
 * anything here.
 */
public final class CoverCache {
    private static final String TAG = "strom";
    private static final String UA = "strom-android/0.1";
    private static final int TIMEOUT_MS = 8000;
    /**
     * A cover is a header image or a screenshot. Anything much larger is
     * not one, and an unbounded read from an arbitrary URL is how a cache
     * dir fills up a device.
     */
    private static final int MAX_BYTES = 8 * 1024 * 1024;

    private final File dir;
    private final LruCache<String, Bitmap> mem;
    /**
     * Small pool: three concurrent fetches keep a scroll fed without
     * competing with the catalog load or a payload download for the link.
     */
    private final ExecutorService pool = Executors.newFixedThreadPool(3);
    private final Handler ui = new Handler(Looper.getMainLooper());
    /**
     * What each tile currently wants. A recycled tile's queued work is
     * dropped rather than drawn over the game the tile now shows. Weak keys
     * so a view that goes away is not held by its own pending request.
     */
    private final Map<ImageView, String> want = new WeakHashMap<ImageView, String>();

    public CoverCache(Context c) {
        dir = new File(c.getCacheDir(), "covers");
        dir.mkdirs();
        // A quarter of the heap, capped: tiles are already downscaled (a
        // 460x215 tile is ~200 KB in RGB_565), so this holds a few hundred
        // and the LRU drops the ones scrolled past instead of the app
        // dying with the catalog half browsed.
        int max = (int) Math.min(Runtime.getRuntime().maxMemory() / 4, 96L * 1024 * 1024);
        mem = new LruCache<String, Bitmap>(max) {
            @Override
            protected int sizeOf(String key, Bitmap value) {
                return value.getByteCount();
            }
        };
    }

    /**
     * Draw {@code url} into {@code target}, cropped to a {@code w} by
     * {@code h} tile. Returns immediately; the image appears when it is
     * ready, and never appears at all if the tile has moved on by then.
     */
    public void into(final String url, final ImageView target, final int w, final int h) {
        if (url == null || url.isEmpty() || w <= 0 || h <= 0) {
            target.setImageBitmap(null);
            return;
        }
        final String key = key(url, w, h);
        synchronized (want) {
            want.put(target, url);
        }
        Bitmap hit = mem.get(key);
        if (hit != null) {
            target.setImageBitmap(hit);
            return;
        }
        // Clear first: this view is recycled, and the previous game's art
        // must not sit under this game's title while the new one loads.
        target.setImageBitmap(null);
        pool.submit(new Runnable() {
            @Override
            public void run() {
                load(url, key, target, w, h);
            }
        });
    }

    /** Forget everything, memory and disk. Offered on the settings screen. */
    public void clear() {
        mem.evictAll();
        File[] fs = dir.listFiles();
        if (fs == null) {
            return;
        }
        for (File f : fs) {
            f.delete();
        }
    }

    public void shutdown() {
        pool.shutdownNow();
    }

    // ---- worker ----------------------------------------------------------

    private void load(String url, String key, ImageView target, int w, int h) {
        if (!wanted(target, url)) {
            return;
        }
        File sized = new File(dir, key + ".jpg");
        Bitmap b = null;
        if (sized.exists()) {
            // Already exactly tile-sized, so no subsampling to work out.
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inPreferredConfig = Bitmap.Config.RGB_565;
            b = BitmapFactory.decodeFile(sized.getPath(), o);
            if (b == null) {
                sized.delete();   // truncated by a kill mid-write
            }
        }
        if (b == null) {
            File miss = new File(dir, hash(url) + ".miss");
            if (miss.exists()) {
                // Art upstream does not have. Retrying it on every scroll
                // past the tile costs a round trip and never succeeds.
                return;
            }
            File part = new File(dir, key + ".part");
            try {
                download(url, part, miss);
                b = crop(part, w, h);
                if (b != null) {
                    write(sized, b);
                }
            } catch (Exception e) {
                // Art is decoration: a failure leaves the title showing.
                Log.d(TAG, "cover " + url + ": " + e);
            } finally {
                part.delete();
            }
        }
        if (b == null) {
            return;
        }
        mem.put(key, b);
        final Bitmap done = b;
        final ImageView view = target;
        final String u = url;
        ui.post(new Runnable() {
            @Override
            public void run() {
                if (wanted(view, u)) {
                    view.setImageBitmap(done);
                }
            }
        });
    }

    private boolean wanted(ImageView target, String url) {
        synchronized (want) {
            return url.equals(want.get(target));
        }
    }

    private void download(String url, File to, File miss) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setRequestProperty("User-Agent", UA);
        c.setConnectTimeout(TIMEOUT_MS);
        c.setReadTimeout(TIMEOUT_MS);
        try {
            int code = c.getResponseCode();
            if (code == 404 || code == 403 || code == 410) {
                // Negative cache, as the desktop launcher does: this URL is
                // a guess for games with no curated art, and a guess that
                // missed stays missed.
                try {
                    new FileOutputStream(miss).close();
                } catch (IOException ignored) {
                    // Losing the marker only costs a retry.
                }
                throw new IOException("http " + code);
            }
            if (code != 200) {
                throw new IOException("http " + code);
            }
            InputStream in = c.getInputStream();
            OutputStream out = new FileOutputStream(to);
            try {
                byte[] buf = new byte[16 * 1024];
                int total = 0;
                int n;
                while ((n = in.read(buf)) > 0) {
                    total += n;
                    if (total > MAX_BYTES) {
                        throw new IOException("cover larger than " + MAX_BYTES + " bytes");
                    }
                    out.write(buf, 0, n);
                }
            } finally {
                out.close();
                in.close();
            }
        } finally {
            c.disconnect();
        }
    }

    /**
     * Decode {@code f} subsampled, then centre-crop it to exactly
     * {@code w} by {@code h}.
     *
     * <p>The crop happens here rather than in the {@code ImageView} so that
     * what lands in both caches is tile-sized: a 1920x620 hero kept at its
     * own size would be 2.4 MB of heap per game.
     */
    private static Bitmap crop(File f, int w, int h) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(f.getPath(), o);
        if (o.outWidth <= 0 || o.outHeight <= 0) {
            return null;
        }
        o.inSampleSize = sample(o.outWidth, o.outHeight, w, h);
        o.inJustDecodeBounds = false;
        // No cover art has an alpha channel, and 565 halves both the decode
        // peak and what the memory cache holds.
        o.inPreferredConfig = Bitmap.Config.RGB_565;
        Bitmap src = BitmapFactory.decodeFile(f.getPath(), o);
        if (src == null) {
            return null;
        }
        Bitmap out = Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565);
        Canvas cv = new Canvas(out);
        float s = Math.max(w / (float) src.getWidth(), h / (float) src.getHeight());
        Matrix m = new Matrix();
        m.setScale(s, s);
        m.postTranslate((w - src.getWidth() * s) / 2f, (h - src.getHeight() * s) / 2f);
        cv.drawBitmap(src, m, new Paint(Paint.FILTER_BITMAP_FLAG));
        src.recycle();
        return out;
    }

    /**
     * The largest power of two that keeps the decoded image at or above
     * tile size, which is what {@code BitmapFactory} accepts.
     */
    static int sample(int srcW, int srcH, int w, int h) {
        int s = 1;
        while (srcW / (s * 2) >= w && srcH / (s * 2) >= h) {
            s *= 2;
        }
        return s;
    }

    private static void write(File to, Bitmap b) {
        // Through a temp file: a half-written cache entry that keeps its
        // final name is a permanently broken tile.
        File tmp = new File(to.getPath() + ".new");
        try {
            OutputStream out = new FileOutputStream(tmp);
            try {
                b.compress(Bitmap.CompressFormat.JPEG, 85, out);
            } finally {
                out.close();
            }
            if (!tmp.renameTo(to)) {
                tmp.delete();
            }
        } catch (IOException e) {
            Log.d(TAG, "cover cache write failed: " + e);
            tmp.delete();
        }
    }

    /** Cache key: the URL's digest plus the size it was cropped to. */
    private static String key(String url, int w, int h) {
        return hash(url) + "-" + w + "x" + h;
    }

    private static String hash(String url) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] d = md.digest(url.getBytes("UTF-8"));
            StringBuilder b = new StringBuilder(d.length * 2);
            for (byte x : d) {
                b.append(Character.forDigit((x >> 4) & 0xf, 16));
                b.append(Character.forDigit(x & 0xf, 16));
            }
            return b.toString();
        } catch (Exception e) {
            // SHA-1 and UTF-8 are both mandatory on every JVM; if this ever
            // fires, a stable-but-colliding name still beats crashing.
            return Integer.toHexString(url.hashCode());
        }
    }
}
