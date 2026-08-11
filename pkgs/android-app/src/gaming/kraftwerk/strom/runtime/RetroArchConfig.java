package gaming.kraftwerk.strom.runtime;

import android.util.Log;

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
 * The retroarch.cfg this client hands to RetroArch, so a couple of settings
 * can be decided here rather than left to whatever the user's RetroArch
 * happens to have.
 *
 * <p>Only reachable by launching {@code RetroActivityFuture} ourselves:
 * {@code CoreSideloadActivity} reads exactly {@code LIBRETRO} and
 * {@code ROM} and builds its own intent, calling
 * {@code UserPreferences.getDefaultConfigPath}, so a {@code CONFIGFILE}
 * extra handed to it never reaches RetroArch at all.
 *
 * <p>RetroArch owns this file between launches: {@code config_save_on_exit}
 * defaults true, so on a clean exit it rewrites it with its complete
 * settings set. That is why this is a read-modify-write of whatever is
 * there rather than a fresh file -- a rewrite would throw away everything
 * the user changed in RetroArch's own menus -- and why the keys we care
 * about are reapplied before every launch instead of once at setup.
 */
public final class RetroArchConfig {
    private static final String TAG = "strom";

    private RetroArchConfig() {
    }

    public static File path() {
        return new File(CoreInstaller.ROOT, "retroarch.cfg");
    }

    /**
     * Write the config RetroArch should start with, preserving every other
     * line already in the file.
     *
     * @param overlay whether the on-screen touch overlay should be drawn
     */
    public static File write(boolean overlay) throws IOException {
        Map<String, String> ours = new LinkedHashMap<String, String>();
        // A touch overlay over a handheld's physical controls is in the
        // way of the game and answers no need. Decided per launch from
        // what is actually attached, so the same install does the right
        // thing on a phone and on a handheld.
        //
        // input_overlay_hide_when_gamepad_connected would be the setting
        // that names this intent, but it does not work for it: RetroArch's
        // Android input driver registers a pad only when an event arrives
        // from it (handle_hotplug is called from the poll loop, nothing
        // enumerates devices at init), so the overlay is drawn over the
        // start of every game until the player presses something. Deciding
        // it here is both earlier and honest about what we know.
        ours.put("input_overlay_enable", overlay ? "true" : "false");

        File f = path();
        List<String> out = new ArrayList<String>();
        if (f.isFile()) {
            BufferedReader r = new BufferedReader(new FileReader(f));
            try {
                String line;
                while ((line = r.readLine()) != null) {
                    String key = keyOf(line);
                    if (key != null && ours.containsKey(key)) {
                        continue;
                    }
                    out.add(line);
                }
            } finally {
                r.close();
            }
        }
        for (Map.Entry<String, String> e : ours.entrySet()) {
            out.add(e.getKey() + " = \"" + e.getValue() + "\"");
        }

        File parent = f.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IOException("cannot create " + parent);
        }
        PrintWriter w = new PrintWriter(f, "UTF-8");
        try {
            for (String line : out) {
                w.println(line);
            }
        } finally {
            w.close();
        }
        Log.i(TAG, "retroarch config " + f + " overlay=" + overlay);
        return f;
    }

    /** The key of a {@code key = "value"} line, or null if it is not one. */
    private static String keyOf(String line) {
        int eq = line.indexOf('=');
        if (eq < 0) {
            return null;
        }
        String key = line.substring(0, eq).trim();
        return key.isEmpty() ? null : key;
    }
}
