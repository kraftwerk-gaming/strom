package gaming.kraftwerk.strom.runtime;

import android.app.ActivityOptions;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Display;

import gaming.kraftwerk.strom.catalog.Game;

import java.io.File;
import java.io.IOException;

/**
 * Hands a prepared game to an installed runtime app.
 *
 * <p>Strom does not execute anything itself. Shared storage is mounted
 * {@code noexec} and an app may not run code it downloaded, so the only
 * legal shape is to fetch the data and let an app that already ships the
 * engine open it.
 */
public final class Handoff {
    private static final String TAG = "strom";

    /** RetroArch's two published package names; the second is the 64-bit build. */
    private static final String[] RETROARCH_PKGS = {
        "com.retroarch", "com.retroarch.aarch64",
    };
    private static final String RETROARCH_SIDELOAD =
        "com.retroarch.browser.debug.CoreSideloadActivity";

    /**
     * WatermelonDS, a melonDS port for handhelds with two physical panels.
     *
     * <p>Preferred over RetroArch for DS games when it is installed,
     * because a DS has two screens and a device like the AYN Thor has two
     * to put them on. RetroArch draws both into one surface, so it can
     * only stack them on a single panel; WatermelonDS drives the panels
     * itself. Chosen at launch rather than recorded per game, so the same
     * catalogue works on a phone, where RetroArch remains the answer.
     */
    private static final String WATERMELON_PKG = "me.magnum.melondualds";
    private static final String WATERMELON_ACTIVITY = "me.magnum.melonds.ui.emulator.EmulatorActivity";
    private static final String WATERMELON_LAUNCH = "me.magnum.melondualds.LAUNCH_ROM";

    /**
     * The second intent goes out after this long. The first one from cold
     * only installs the core: its RetroActivityFuture is force-finished as
     * the sideload activity tears itself down, so nothing runs until a
     * second, identical intent arrives.
     */
    private static final long SECOND_FIRE_MS = 6000;

    public static final class NotInstalled extends IOException {
        public NotInstalled(String m) {
            super(m);
        }
    }

    private Handoff() {
    }

    public static boolean available(Context c, String backend) {
        return installedPackage(c, backend) != null;
    }

    private static String installedPackage(Context c, String backend) {
        if (backend == null) {
            return null;
        }
        String[] candidates;
        if (backend.equals("retroarch")) {
            candidates = RETROARCH_PKGS;
        } else if (backend.equals("gamenative")) {
            candidates = new String[] { "app.gamenative" };
        } else if (backend.equals("dolphin")) {
            candidates = new String[] { "org.dolphinemu.dolphinemu" };
        } else {
            return null;
        }
        PackageManager pm = c.getPackageManager();
        for (String p : candidates) {
            try {
                pm.getPackageInfo(p, 0);
                return p;
            } catch (PackageManager.NameNotFoundException e) {
                // try the next one
            }
        }
        return null;
    }

    /**
     * @param payloadDir the unpacked tree in shared storage, or the payload
     *                   file itself when the game is a single ROM
     */
    public static void launch(Context c, Game g, File payloadDir) throws IOException {
        String pkg = installedPackage(c, g.backend);
        if (pkg == null) {
            throw new NotInstalled("no app installed for backend '" + g.backend + "'");
        }
        if ("retroarch".equals(g.backend)) {
            // A DS game on a two-panel handheld belongs in an emulator that
            // can use both panels, when the user has one installed.
            if (isNintendoDs(g) && installed(c, WATERMELON_PKG)) {
                launchWatermelon(c, g, payloadDir);
                return;
            }
            launchRetroArch(c, pkg, g, payloadDir);
            return;
        }
        // GameNative and Dolphin are described in docs/android.md, but the
        // decisive facts for both are still marked device-only there: for
        // GameNative whether its `A:` drive repoint actually boots the game
        // we point it at, and for Dolphin the intent shape has not been
        // measured against a running app at all. Inventing an intent here
        // would produce a silent no-op on a phone, which is worse than a
        // refusal that names what is missing.
        throw new IOException("backend '" + g.backend
            + "' is not wired up yet: its handoff is unverified on a real device"
            + " (see docs/android.md)");
    }

    private static boolean installed(Context c, String pkg) {
        try {
            c.getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /** Whether the manifest sends this game to a melonDS-family core. */
    private static boolean isNintendoDs(Game g) {
        return g.retroarchCore != null && g.retroarchCore.startsWith("melonds");
    }

    /**
     * Hand a DS ROM to WatermelonDS, which puts one screen on each panel.
     *
     * <p>Its EmulatorActivity takes the ROM as the intent's data URI, not
     * as an extra. That has to be a {@code content:} URI: a targetSdk 24+
     * app throws FileUriExposedException when it passes {@code file:} to
     * another process. The payload already sits in public Downloads, so
     * MediaStore can name it, which avoids shipping a FileProvider and the
     * res/xml tree that would need.
     */
    private static void launchWatermelon(Context c, Game g, File payloadDir) throws IOException {
        File rom = romIn(payloadDir, g.launchTarget);
        if (rom == null) {
            throw new IOException("launch target '" + g.launchTarget
                + "' not found under " + payloadDir);
        }
        Uri uri = MediaStoreUri.of(c, rom);
        Intent intent = new Intent(WATERMELON_LAUNCH);
        intent.setComponent(new ComponentName(WATERMELON_PKG, WATERMELON_ACTIVITY));
        intent.setData(uri);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);

        Log.i(TAG, "handoff -> " + WATERMELON_PKG + " (dual screen) rom=" + rom + " uri=" + uri);
        // Pinned to the built-in panel instead of inheriting ours. A
        // dual-screen emulator puts one DS screen in its own window and
        // presents the other onto a secondary display, so started on the
        // secondary display it has nowhere left to present and stacks both
        // DS screens in the one window. That is what a user sees after
        // opening this client on the external panel, which the Thor's
        // launcher makes easy to do by accident. Which physical panel then
        // shows which DS screen is the emulator's own setting to make.
        ActivityOptions onBuiltIn = ActivityOptions.makeBasic();
        onBuiltIn.setLaunchDisplayId(Display.DEFAULT_DISPLAY);
        c.startActivity(intent, onBuiltIn.toBundle());
    }

    private static void launchRetroArch(final Context c, final String pkg, Game g, File payloadDir)
        throws IOException {
        File core = CoreInstaller.coreFile(g.retroarchCore);
        if (!core.isFile()) {
            throw new IOException("core not downloaded: " + core);
        }
        File rom = romIn(payloadDir, g.launchTarget);
        if (rom == null) {
            throw new IOException("launch target '" + g.launchTarget
                + "' not found under " + payloadDir);
        }

        final Intent intent = new Intent();
        intent.setComponent(new ComponentName(pkg, RETROARCH_SIDELOAD));
        intent.putExtra("LIBRETRO", core.getAbsolutePath());
        intent.putExtra("ROM", rom.getAbsolutePath());
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        // Always send it twice rather than tracking whether the core is
        // already installed. RetroArch's private cores directory is
        // unreadable to us, so any such record is a guess about another
        // app's state, and a first attempt that failed (its cores dir did
        // not exist yet, say) would leave the guess permanently wrong and
        // the game unlaunchable. The second intent costs one re-copy of a
        // few-MB core and is harmless when the first already worked.
        Log.i(TAG, "handoff -> " + pkg + " core=" + core + " rom=" + rom);
        c.startActivity(intent);

        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                Log.i(TAG, "handoff -> " + pkg + " second intent");
                try {
                    c.startActivity(intent);
                } catch (Exception e) {
                    Log.w(TAG, "second intent failed", e);
                }
            }
        }, SECOND_FIRE_MS);
    }

    /**
     * Find the file to hand over. The manifest names it (the recipe's
     * `executable`, which is the same path the desktop launches), so the
     * common case is an exact lookup; searching is only the fallback for a
     * payload whose tree has an extra wrapping directory.
     */
    private static File romIn(File payload, String target) {
        if (payload.isFile()) {
            return payload;
        }
        if (target != null && !target.isEmpty()) {
            File exact = new File(payload, target);
            if (exact.isFile()) {
                return exact;
            }
            File found = findByName(payload, new File(target).getName(), 4);
            if (found != null) {
                return found;
            }
            return null;
        }
        // No named target: a single-file payload is unambiguous, anything
        // else would be a guess and a wrong guess boots the wrong thing.
        File[] kids = payload.listFiles();
        if (kids != null && kids.length == 1 && kids[0].isFile()) {
            return kids[0];
        }
        return null;
    }

    private static File findByName(File dir, String name, int depth) {
        if (depth < 0) {
            return null;
        }
        File[] kids = dir.listFiles();
        if (kids == null) {
            return null;
        }
        for (File f : kids) {
            if (f.isFile() && f.getName().equalsIgnoreCase(name)) {
                return f;
            }
        }
        for (File f : kids) {
            if (f.isDirectory()) {
                File deeper = findByName(f, name, depth - 1);
                if (deeper != null) {
                    return deeper;
                }
            }
        }
        return null;
    }
}
