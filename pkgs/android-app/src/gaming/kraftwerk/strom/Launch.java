package gaming.kraftwerk.strom;

import android.content.Context;
import android.util.Log;

import gaming.kraftwerk.strom.catalog.Game;
import gaming.kraftwerk.strom.catalog.Layer;
import gaming.kraftwerk.strom.catalog.Options;
import gaming.kraftwerk.strom.ipfs.Fetcher;
import gaming.kraftwerk.strom.ipfs.UnixFs;
import gaming.kraftwerk.strom.runtime.CoreInstaller;
import gaming.kraftwerk.strom.runtime.Handoff;

import java.io.File;
import java.io.IOException;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

/**
 * Everything between "play this" and the runtime taking over: install a
 * core if the backend needs one, fetch and verify the payload, merge the
 * mod layers the player picked, hand off.
 *
 * <p>Deliberately free of views. The on-screen list and the automation
 * entry point ({@link LaunchActivity}) are two callers of exactly this, so
 * a launch driven over adb exercises the same path a player does rather
 * than a parallel one that can drift.
 */
public final class Launch {
    private static final String TAG = "strom";

    /** Where the caller shows progress. Called from a worker thread. */
    public interface Progress {
        void say(String message);
    }

    /**
     * What a launch attempt ended as, so a caller can react without
     * parsing message text.
     */
    public enum Result {
        LAUNCHED,
        /** A one-time manual step is needed; {@code message} says which. */
        NEEDS_SETUP,
        /** The picks cannot be honoured; {@code message} says why. */
        REFUSED,
        FAILED,
    }

    public static final class Outcome {
        public final Result result;
        public final String message;
        /** True when a stale mod layer means the payload must be redownloaded. */
        public final boolean staleLayers;

        Outcome(Result r, String m, boolean stale) {
            this.result = r;
            this.message = m;
            this.staleLayers = stale;
        }
    }

    private Launch() {
    }

    /**
     * @param picks the player's option choices, non-default values only;
     *              may be empty
     */
    public static Outcome run(Context c, Game g, Map<String, String> picks, Progress p) {
        try {
            if ("retroarch".equals(g.backend)) {
                p.say("fetching core " + g.retroarchCore);
                CoreInstaller.ensure(g.retroarchCore);
            }

            File dir = CoreInstaller.payloadDir(g);
            boolean have = present(dir);
            // What the tree already carries, so a mod is fetched once and a
            // mod that was switched back off is noticed.
            Set<String> applied = have ? Applied.read(dir) : new LinkedHashSet<String>();
            Options.Plan plan = Options.plan(g, picks, applied);
            if (plan.problem != null) {
                // Launching regardless would run a tree that is not what was
                // picked: a mod the player looks for and cannot find, or one
                // they turned off and still get.
                return new Outcome(Result.REFUSED, plan.problem, !plan.stale.isEmpty());
            }

            if (!have) {
                // A single-file payload extracts to a file and a directory
                // payload to a tree, and which one it is is only known once
                // the DAG arrives. Land it on a scratch path, then put it
                // where it belongs.
                File part = new File(dir.getAbsolutePath() + ".part");
                p.say("fetching payload");
                UnixFs.Stats st = Fetcher.fetchAndExtract(g.payloadCid, part, bytes(p, null));
                place(part, dir, g);
                p.say("verified " + st.blocks + " blocks, " + human(st.bytesOut));
                // A base that was just unpacked carries no mods, whatever an
                // interrupted earlier attempt recorded.
                applied.clear();
                Applied.write(dir, applied);
            } else {
                p.say("already downloaded");
            }

            for (Layer l : plan.fetch) {
                p.say("fetching mod " + l.name);
                UnixFs.Stats ls = Fetcher.fetchAndMerge(l.cid, dir, l.name, bytes(p, l.name));
                // Recorded per layer, and only once its whole tree is
                // verified and merged: an interrupted mod is refetched rather
                // than remembered as applied.
                applied.add(l.name);
                Applied.write(dir, applied);
                p.say("merged " + l.name + ", " + human(ls.bytesOut));
            }

            p.say("handing off");
            Handoff.launch(c, g, dir);
            return new Outcome(Result.LAUNCHED, "launched", false);
        } catch (Handoff.NeedsSetup e) {
            // An instruction, not a fault: printing the exception class in
            // front of it turns "here is what to do" into "something
            // crashed".
            Log.i(TAG, "setup needed for " + g.slug + ": " + e.getMessage());
            return new Outcome(Result.NEEDS_SETUP, e.getMessage(), false);
        } catch (Exception e) {
            Log.w(TAG, "launch failed for " + g.slug, e);
            return new Outcome(Result.FAILED, "failed: " + e, false);
        }
    }

    private static Fetcher.Progress bytes(final Progress p, final String label) {
        return new Fetcher.Progress() {
            @Override
            public void bytes(long soFar) {
                p.say(label == null
                    ? "fetching " + human(soFar)
                    : "fetching " + label + " " + human(soFar));
            }

            @Override
            public void gatewayFailed(String gateway, java.io.IOException e) {
                Log.w(TAG, "fetch " + (label == null ? "" : label + " ")
                    + "via " + gateway + " failed: " + e);
            }
        };
    }

    static boolean present(File dir) {
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
    static void place(File part, File dir, Game g) throws IOException {
        if (part.isDirectory()) {
            if (!part.renameTo(dir)) {
                throw new IOException("cannot move " + part + " to " + dir);
            }
            return;
        }
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new IOException("cannot create " + dir);
        }
        String name = (g.payloadName != null && !g.payloadName.isEmpty())
            ? g.payloadName : g.slug;
        File dst = new File(dir, name);
        if (!part.renameTo(dst)) {
            throw new IOException("cannot move " + part + " to " + dst);
        }
    }

    public static String human(long n) {
        if (n < 1024) {
            return n + " B";
        }
        if (n < 1024 * 1024) {
            return (n / 1024) + " KiB";
        }
        if (n < 1024L * 1024 * 1024) {
            return (n / (1024 * 1024)) + " MiB";
        }
        return String.format("%.1f GiB", n / (1024.0 * 1024 * 1024));
    }
}
