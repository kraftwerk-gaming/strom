package gaming.kraftwerk.strom.runtime;

import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Environment;
import android.provider.Settings;
import android.util.Log;
import android.view.Display;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Puts one 3DS screen on each panel, by writing the setting into Azahar's
 * own config.
 *
 * <p>Azahar takes no settings from an intent, and its config lives in
 * whichever folder the player granted it through the system picker -- a
 * path this client is never told. Azahar opens that picker with no initial
 * location, so there is no way to steer the choice either without telling
 * the player exactly where to tap.
 *
 * <p>So the folder is found instead of dictated. That needs all-files
 * access, which is why this client asks for it: not to read the player's
 * storage, but to write two lines into one ini belonging to another app.
 * Without the permission everything still works and Azahar keeps its own
 * layout; the difference is a screen on each panel rather than both in one
 * window.
 *
 * <p>What cannot be done from here at all is the on-screen input overlay.
 * That is {@code EmulationMenuSettings_ShowOverlay} in Azahar's default
 * SharedPreferences, inside its private data directory, with no config key
 * and no intent behind it. On a device with real controls it is one switch
 * in Azahar's own in-game menu, and no other app can reach it.
 */
public final class AzaharConfig {
    private static final String TAG = "strom";

    /**
     * Directories Azahar creates in its user folder. Two of these plus a
     * readable config are taken as identifying it, which is a signature
     * rather than a contract: it is the emulator's layout on disk, not
     * anything it promises.
     */
    private static final String[] MARKS = { "sdmc", "nand", "sysdata", "shaders" };

    private AzaharConfig() {
    }

    /** Whether this client may write outside its own files. */
    public static boolean canWrite() {
        return Environment.isExternalStorageManager();
    }

    /** Whether there is a second panel for a screen to go on. */
    public static boolean secondDisplay(Context c) {
        DisplayManager dm = (DisplayManager) c.getSystemService(Context.DISPLAY_SERVICE);
        if (dm == null) {
            return false;
        }
        Display[] ds = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION);
        return ds != null && ds.length > 0;
    }

    /** The settings screen that grants all-files access to this app. */
    public static Intent grantIntent(Context c) {
        Intent i = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
        i.setData(Uri.parse("package:" + c.getPackageName()));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return i;
    }

    /**
     * Write the two-panel settings into Azahar's config, if all of it is
     * possible: the permission is held, the device has a second panel, and
     * the folder can be found.
     *
     * @return true when the config was written
     */
    public static boolean apply(Context c) {
        if (!canWrite() || !secondDisplay(c)) {
            return false;
        }
        File dir = findUserDir();
        if (dir == null) {
            Log.i(TAG, "azahar: no user folder found to configure");
            return false;
        }

        Map<String, String> ours = new LinkedHashMap<String, String>();
        // Azahar's own switch for presenting onto a second physical
        // display, then what each panel shows: the touch screen on the
        // second one, and the main window reduced to a single screen so it
        // does not draw the touch screen twice.
        ours.put("enable_secondary_display", "true");
        ours.put("secondary_display_layout", "2");
        ours.put("layout_option", "1");

        File f = new File(new File(dir, "config"), "config.ini");
        try {
            write(f, ours);
            Log.i(TAG, "azahar configured for two panels: " + f);
            return true;
        } catch (IOException e) {
            Log.w(TAG, "could not configure azahar at " + f, e);
            return false;
        }
    }

    /**
     * Azahar's user folder, or null.
     *
     * <p>Shallow on purpose. The picker will not grant the storage root or
     * a top-level media directory, so what a player can actually choose is
     * a directory one or two levels down, and a full walk of shared storage
     * to find one ini would be both slow and far more reading of their files
     * than this is for.
     */
    private static File findUserDir() {
        File root = Environment.getExternalStorageDirectory();
        List<File> queue = new ArrayList<File>();
        queue.add(root);
        for (int depth = 0; depth < 2 && !queue.isEmpty(); depth++) {
            List<File> next = new ArrayList<File>();
            for (File d : queue) {
                File[] kids = d.listFiles();
                if (kids == null) {
                    continue;
                }
                for (File k : kids) {
                    if (!k.isDirectory() || k.getName().startsWith(".")) {
                        continue;
                    }
                    if (looksLikeAzahar(k)) {
                        return k;
                    }
                    next.add(k);
                }
            }
            queue = next;
        }
        return null;
    }

    private static boolean looksLikeAzahar(File d) {
        if (!new File(new File(d, "config"), "config.ini").isFile()) {
            return false;
        }
        int marks = 0;
        for (String m : MARKS) {
            if (new File(d, m).isDirectory()) {
                marks++;
            }
        }
        return marks >= 2;
    }

    /**
     * Set keys in an ini, leaving every other line alone.
     *
     * <p>A read-modify-write because Azahar owns this file: it rewrites the
     * whole thing with its complete settings on exit, so anything the player
     * changed has to survive, and ours have to be reasserted.
     */
    private static void write(File f, Map<String, String> ours) throws IOException {
        Map<String, String> todo = new LinkedHashMap<String, String>(ours);
        List<String> out = new ArrayList<String>();
        BufferedReader r = new BufferedReader(new FileReader(f));
        try {
            String line;
            while ((line = r.readLine()) != null) {
                String key = keyOf(line);
                if (key != null && todo.containsKey(key)) {
                    out.add(key + " = " + todo.remove(key));
                } else {
                    out.add(line);
                }
            }
        } finally {
            r.close();
        }
        for (Map.Entry<String, String> e : todo.entrySet()) {
            int at = out.indexOf("[Layout]");
            if (at < 0) {
                out.add("[Layout]");
                at = out.size() - 1;
            }
            out.add(at + 1, e.getKey() + " = " + e.getValue());
        }

        PrintWriter w = new PrintWriter(f, "UTF-8");
        try {
            for (String line : out) {
                w.println(line);
            }
        } finally {
            w.close();
        }
    }

    private static String keyOf(String line) {
        int eq = line.indexOf('=');
        if (eq < 0) {
            return null;
        }
        String key = line.substring(0, eq).trim();
        return key.isEmpty() ? null : key;
    }
}
