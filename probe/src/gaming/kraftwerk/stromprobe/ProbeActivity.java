package gaming.kraftwerk.stromprobe;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;

/**
 * Fires the runtime-app handoff intents from a real application uid, which is
 * the one thing `adb shell am start` cannot tell us: that runs as uid 2000
 * (shell) and is permitted things an ordinary app is not.
 *
 * Also measures where our client is actually allowed to put a core so that
 * RetroArch can read it back. Three candidate locations, cheapest first:
 *
 *   A  /storage/emulated/0/Strom/  -- arbitrary shared storage. On API 30+
 *      this needs MANAGE_EXTERNAL_STORAGE, an all-files grant the user must
 *      hand over through a Settings screen.
 *   B  getExternalFilesDir()       -- our own dir under Android/data. Needs
 *      no permission at all. Readable by RetroArch only if a known absolute
 *      path can be traversed into it (Android/data is drwxrws--x).
 *   C  getFilesDir()               -- internal. Definitely unreadable by
 *      another app, listed only to bound the answer.
 */
public class ProbeActivity extends Activity {
    private static final String TAG = "stromprobe";

    private static final String RA_PKG = "com.retroarch";
    private static final String RA_SIDELOAD =
        "com.retroarch.browser.debug.CoreSideloadActivity";
    private static final String RA_FUTURE =
        "com.retroarch.browser.retroactivity.RetroActivityFuture";

    private static void probeWrite(String label, File dir) {
        try {
            if (dir == null) { Log.i(TAG, "write " + label + ": null dir"); return; }
            if (!dir.exists() && !dir.mkdirs()) {
                Log.i(TAG, "write " + label + ": FAIL mkdirs " + dir);
                return;
            }
            File f = new File(dir, "probe-write.txt");
            FileOutputStream os = new FileOutputStream(f);
            os.write("strom\n".getBytes());
            os.close();
            Log.i(TAG, "write " + label + ": OK " + f + " (" + f.length() + "B)");
        } catch (Exception e) {
            Log.i(TAG, "write " + label + ": FAIL " + dir + " -- " + e);
        }
    }

    /**
     * Write into the public Downloads collection through MediaStore, which
     * needs no permission on API 30+, then resolve the real filesystem path
     * so it can be handed to a runtime app that takes paths, not URIs.
     */
    private String probeMediaStore(String name, byte[] payload) {
        try {
            ContentValues cv = new ContentValues();
            cv.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            cv.put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Strom");
            Uri uri = getContentResolver().insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
            if (uri == null) { Log.i(TAG, "mediastore " + name + ": insert returned null"); return null; }
            java.io.OutputStream os = getContentResolver().openOutputStream(uri);
            os.write(payload);
            os.close();

            String path = null;
            Cursor c = getContentResolver().query(uri,
                new String[] { MediaStore.MediaColumns.DATA }, null, null, null);
            if (c != null) {
                if (c.moveToFirst()) path = c.getString(0);
                c.close();
            }
            Log.i(TAG, "mediastore " + name + ": OK uri=" + uri + " path=" + path);
            return path;
        } catch (Exception e) {
            Log.i(TAG, "mediastore " + name + ": FAIL " + e);
            return null;
        }
    }

    private static byte[] slurp(File f) {
        try {
            java.io.FileInputStream in = new java.io.FileInputStream(f);
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
            in.close();
            return bo.toByteArray();
        } catch (Exception e) {
            Log.i(TAG, "slurp failed: " + e);
            return null;
        }
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        PackageManager pm = getPackageManager();

        Log.i(TAG, "isExternalStorageManager=" + Environment.isExternalStorageManager());

        probeWrite("A shared", new File("/storage/emulated/0/Strom/cores"));
        probeWrite("B extfiles", getExternalFilesDir("cores"));
        probeWrite("C internal", new File(getFilesDir(), "cores"));
        probeWrite("D download-direct", new File("/storage/emulated/0/Download/Strom"));
        // Can we drop a PSX BIOS where RetroArch looks for it? This decides
        // whether the 15 BIOS-bearing games are reachable at all.
        probeWrite("E retroarch-system", new File("/storage/emulated/0/RetroArch/system"));
        probeWrite("F retroarch-root", new File("/storage/emulated/0/RetroArch"));

        for (String pkg : new String[] { RA_PKG, "app.gamenative", "org.dolphinemu.dolphinemu" }) {
            try {
                ApplicationInfo ai = pm.getApplicationInfo(pkg, 0);
                Log.i(TAG, "visible: " + pkg + " dataDir=" + ai.dataDir);
            } catch (PackageManager.NameNotFoundException e) {
                Log.i(TAG, "NOT visible: " + pkg);
            }
        }

        // Hand RetroArch a core sitting in OUR external files dir. If it can
        // read that, the client needs no storage permission whatsoever.
        String core = getIntent().getStringExtra("core");
        String rom = getIntent().getStringExtra("rom");
        if (core == null) core = new File(getExternalFilesDir("cores"),
            "gambatte_libretro_android.so").getAbsolutePath();
        if (rom == null) rom = new File(getExternalFilesDir("games"),
            "pokemon-blue.gb").getAbsolutePath();

        if ("download".equals(getIntent().getStringExtra("via"))) {
            // The shape the client would actually ship: a plain File copy into
            // the public Downloads tree. No permission, no MediaStore, and no
            // dedup suffix mangling the filename.
            File dst = new File("/storage/emulated/0/Download/Strom");
            dst.mkdirs();
            String[][] jobs = {
                { "cores", "gambatte_libretro_android.so" },
                { "games", "pokemon-blue.gb" },
            };
            for (String[] j : jobs) {
                File src = new File(getExternalFilesDir(j[0]), j[1]);
                File out = new File(dst, j[1]);
                try {
                    java.io.FileInputStream in = new java.io.FileInputStream(src);
                    FileOutputStream os = new FileOutputStream(out);
                    byte[] buf = new byte[65536];
                    int n;
                    while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
                    in.close();
                    os.close();
                    Log.i(TAG, "copied -> " + out + " (" + out.length() + "B)");
                } catch (Exception e) {
                    Log.i(TAG, "copy FAILED " + out + " -- " + e);
                }
            }
            core = new File(dst, "gambatte_libretro_android.so").getAbsolutePath();
            rom = new File(dst, "pokemon-blue.gb").getAbsolutePath();
        }

        if ("mediastore".equals(getIntent().getStringExtra("via"))) {
            byte[] cbytes = slurp(new File(getExternalFilesDir("cores"),
                "gambatte_libretro_android.so"));
            byte[] rbytes = slurp(new File(getExternalFilesDir("games"),
                "pokemon-blue.gb"));
            if (cbytes != null && rbytes != null) {
                String cp = probeMediaStore("gambatte_libretro_android.so", cbytes);
                String rp = probeMediaStore("pokemon-blue.gb", rbytes);
                if (cp != null) core = cp;
                if (rp != null) rom = rp;
            }
        }

        File cf = new File(core);
        Log.i(TAG, "core path=" + core + " exists=" + cf.exists() + " size=" + cf.length()
                 + " canRead=" + cf.canRead());

        Intent sideload = new Intent();
        sideload.setComponent(new ComponentName(RA_PKG, RA_SIDELOAD));
        sideload.putExtra("LIBRETRO", core);
        sideload.putExtra("ROM", rom);
        Log.i(TAG, "resolveActivity(sideload)=" + sideload.resolveActivity(pm));
        Log.i(TAG, "resolveActivity(future)=" + new Intent().setComponent(
            new ComponentName(RA_PKG, RA_FUTURE)).resolveActivity(pm));

        try {
            startActivity(sideload);
            Log.i(TAG, "startActivity OK");
        } catch (Exception e) {
            Log.e(TAG, "startActivity FAILED: " + e);
        }
        finish();
    }
}
