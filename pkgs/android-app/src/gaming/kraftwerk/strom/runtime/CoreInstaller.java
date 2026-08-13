package gaming.kraftwerk.strom.runtime;

import android.os.Build;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import gaming.kraftwerk.strom.catalog.Game;

/**
 * Downloads libretro cores from the official Android buildbot.
 *
 * <p>Cores live beside the payloads in public shared storage rather than in
 * our own app directory, because RetroArch has to read the file and no app
 * can read into another's {@code Android/data}.
 */
public final class CoreInstaller {
    private static final String TAG = "strom";
    private static final String BUILDBOT =
        "https://buildbot.libretro.com/nightly/android/latest/";

    /** Public Downloads is the one place both processes can reach without a grant. */
    public static final File ROOT = new File("/storage/emulated/0/Download/Strom");
    private static final File CORES = new File(ROOT, "cores");

    /**
     * The one folder a user registers in GameNative, holding every
     * gamenative game as a subfolder. Registering the parent means one
     * picker trip ever instead of one per game.
     */
    public static final File GAMENATIVE_PARENT = new File(ROOT, "games");

    private CoreInstaller() {
    }

    public static File coreFile(String coreName) {
        return new File(CORES, coreName);
    }

    /** The ABI directory the buildbot publishes for this device. */
    private static String abi() {
        String[] abis = Build.SUPPORTED_ABIS;
        return (abis != null && abis.length > 0) ? abis[0] : "arm64-v8a";
    }

    /**
     * Ensure a core is present, downloading and unzipping it if not.
     *
     * @return the {@code .so} on disk
     */
    public static File ensure(String coreName) throws IOException {
        if (coreName == null || coreName.isEmpty()) {
            throw new IOException("game does not name a libretro core");
        }
        File out = coreFile(coreName);
        if (out.isFile() && out.length() > 0) {
            return out;
        }
        if (!CORES.isDirectory() && !CORES.mkdirs()) {
            throw new IOException("cannot create " + CORES);
        }

        String url = BUILDBOT + abi() + "/" + coreName + ".zip";
        Log.i(TAG, "fetching core " + url);

        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try {
            c.setConnectTimeout(20000);
            c.setReadTimeout(60000);
            int code = c.getResponseCode();
            if (code != 200) {
                throw new IOException("HTTP " + code + " fetching core " + coreName
                    + " for " + abi());
            }
            ZipInputStream zin = new ZipInputStream(c.getInputStream());
            try {
                ZipEntry e;
                while ((e = zin.getNextEntry()) != null) {
                    String name = e.getName();
                    // The archive is trusted, but a zip entry is still
                    // attacker-controlled input the moment a mirror is.
                    if (name.contains("..") || name.indexOf('/') >= 0
                        || name.indexOf('\\') >= 0) {
                        throw new IOException("refusing zip entry '" + name + "'");
                    }
                    if (!name.endsWith(".so")) {
                        continue;
                    }
                    File tmp = new File(CORES, name + ".part");
                    FileOutputStream fo = new FileOutputStream(tmp);
                    try {
                        byte[] buf = new byte[65536];
                        int n;
                        while ((n = zin.read(buf)) > 0) {
                            fo.write(buf, 0, n);
                        }
                    } finally {
                        fo.close();
                    }
                    File dst = new File(CORES, name);
                    if (!tmp.renameTo(dst)) {
                        throw new IOException("cannot place " + dst);
                    }
                    Log.i(TAG, "core ready " + dst + " (" + dst.length() + " bytes)");
                    return dst;
                }
            } finally {
                zin.close();
            }
        } finally {
            c.disconnect();
        }
        throw new IOException("no .so inside the core archive for " + coreName);
    }

    /** Where a game's payload is unpacked. */
    public static File payloadDir(String slug) {
        return new File(ROOT, slug);
    }

    /**
     * Where THIS game's payload is unpacked.
     *
     * <p>A gamenative game lands one level deeper, under a single shared
     * parent. GameNative's custom-game library is literally a list of
     * registered folder paths, each registered once by the user in its own
     * UI, and it reads the tree in place rather than importing it. So every
     * gamenative game has to be a subfolder of the one folder the user
     * registered, or it is not in the library at all. See docs/android.md.
     */
    public static File payloadDir(Game g) {
        if ("gamenative".equals(g.backend)) {
            return new File(GAMENATIVE_PARENT, g.slug);
        }
        return new File(ROOT, g.slug);
    }
}
