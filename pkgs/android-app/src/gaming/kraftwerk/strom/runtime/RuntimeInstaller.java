package gaming.kraftwerk.strom.runtime;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/**
 * Installs a runtime app, but only when the device does not already have
 * one.
 *
 * <p>Android will not let an app install another silently, and should
 * not: the most this can do is fetch a pinned build, check it against its
 * hash, and hand it to the system installer for the user to confirm. An
 * app already present is left alone whatever its version -- it may be
 * newer than our pin, installed from F-Droid or Obtainium or a store, and
 * replacing someone's working emulator to satisfy a version table would
 * be rude and occasionally destructive.
 */
public final class RuntimeInstaller {
    private static final String TAG = "strom";
    private static final File DIR = new File(CoreInstaller.ROOT, "runtimes");

    public interface Progress {
        void bytes(long soFar, long total);
    }

    private RuntimeInstaller() {
    }

    /** True when some app that can serve this backend is already present. */
    public static boolean satisfied(Context c, String backend) {
        return Handoff.available(c, backend);
    }

    /** What we would install for this backend, or null if nothing. */
    public static String offerLabel(String backend) {
        Runtimes.Spec s = Runtimes.forBackend(backend);
        return s == null ? null : s.label;
    }

    public static long offerSize(String backend) {
        Runtimes.Spec s = Runtimes.forBackend(backend);
        return s == null ? 0 : s.size;
    }

    /**
     * Fetch the pinned APK for a backend and open the system installer.
     *
     * <p>Returns once the installer has been launched; whether the user
     * accepts is theirs to decide and is observed later by asking the
     * package manager again.
     */
    public static void install(Context c, String backend, Progress p) throws IOException {
        Runtimes.Spec spec = Runtimes.forBackend(backend);
        if (spec == null) {
            throw new IOException("no runtime app is pinned for backend '" + backend + "'");
        }
        install(c, spec, p);
    }

    static void install(Context c, Runtimes.Spec spec, Progress p) throws IOException {
        if (isInstalled(c, spec.pkg)) {
            Log.i(TAG, spec.pkg + " already installed, leaving it alone");
            return;
        }
        File apk = fetch(spec, p);
        Uri uri = MediaStoreUri.of(c, apk);

        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
        Log.i(TAG, "installing " + spec.label + " from " + apk);
        c.startActivity(intent);
    }

    static boolean isInstalled(Context c, String pkg) {
        try {
            c.getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /**
     * Download the pinned APK, or reuse one already downloaded and still
     * matching its hash.
     */
    private static File fetch(Runtimes.Spec spec, Progress p) throws IOException {
        if (!DIR.isDirectory() && !DIR.mkdirs()) {
            throw new IOException("cannot create " + DIR);
        }
        File out = new File(DIR, spec.pkg + ".apk");
        if (out.isFile() && spec.sha256.equals(sha256(out))) {
            return out;
        }

        File part = new File(DIR, spec.pkg + ".apk.part");
        HttpURLConnection conn = (HttpURLConnection) new URL(spec.url).openConnection();
        try {
            conn.setInstanceFollowRedirects(true);
            conn.setConnectTimeout(20000);
            conn.setReadTimeout(60000);
            conn.setRequestProperty("User-Agent", "curl/8.4.0");
            int code = conn.getResponseCode();
            if (code != 200) {
                throw new IOException("HTTP " + code + " fetching " + spec.url);
            }
            InputStream in = conn.getInputStream();
            FileOutputStream fo = new FileOutputStream(part);
            try {
                byte[] buf = new byte[65536];
                long total = 0;
                int n;
                while ((n = in.read(buf)) > 0) {
                    fo.write(buf, 0, n);
                    total += n;
                    if (p != null) {
                        p.bytes(total, spec.size);
                    }
                }
            } finally {
                fo.close();
            }
        } finally {
            conn.disconnect();
        }

        String got = sha256(part);
        if (!spec.sha256.equals(got)) {
            // Refuse rather than install: this is another app's binary,
            // about to be granted whatever the user grants it.
            part.delete();
            throw new IOException(spec.label + " did not match its pinned hash"
                + " (expected " + spec.sha256 + ", got " + got + ")");
        }
        if (!part.renameTo(out)) {
            throw new IOException("cannot place " + out);
        }
        return out;
    }

    private static String sha256(File f) throws IOException {
        MessageDigest md;
        try {
            md = MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IOException("no SHA-256", e);
        }
        InputStream in = new java.io.FileInputStream(f);
        try {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
        } finally {
            in.close();
        }
        StringBuilder sb = new StringBuilder();
        for (byte b : md.digest()) {
            sb.append(Character.forDigit((b >> 4) & 0xf, 16));
            sb.append(Character.forDigit(b & 0xf, 16));
        }
        return sb.toString();
    }
}
