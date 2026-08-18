package gaming.kraftwerk.strom;

import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Which mod layers are already unpacked into a game directory.
 *
 * <p>Kept beside the tree rather than in preferences: the tree is what the
 * record describes, so deleting the game directory forgets it too, which is
 * the correct behaviour and needs no cleanup pass.
 */
public final class Applied {
    private static final String TAG = "strom";
    private static final String MARKER = ".strom-layers";

    private Applied() {
    }

    public static Set<String> read(File dir) {
        Set<String> out = new LinkedHashSet<String>();
        File f = new File(dir, MARKER);
        if (!f.isFile()) {
            // Either nothing was ever merged, or this tree predates the
            // marker; both mean every picked mod still has to be fetched,
            // and merging one twice changes nothing.
            return out;
        }
        try {
            BufferedReader r = new BufferedReader(
                new InputStreamReader(new FileInputStream(f), "UTF-8"));
            try {
                for (String line = r.readLine(); line != null; line = r.readLine()) {
                    String name = line.trim();
                    if (!name.isEmpty()) {
                        out.add(name);
                    }
                }
            } finally {
                r.close();
            }
        } catch (IOException e) {
            Log.w(TAG, "cannot read " + f, e);
        }
        return out;
    }

    public static void write(File dir, Set<String> names) throws IOException {
        Writer w = new OutputStreamWriter(
            new FileOutputStream(new File(dir, MARKER)), "UTF-8");
        try {
            for (String name : names) {
                w.write(name);
                w.write('\n');
            }
        } finally {
            w.close();
        }
    }
}
