package gaming.kraftwerk.strom.runtime;

import android.app.ActivityOptions;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Display;
import android.view.InputDevice;

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
     * RetroArch's own game activity, exported, and the only entry that
     * takes a caller-supplied CONFIGFILE. The sideload activity above
     * builds its own intent and calls UserPreferences.getDefaultConfigPath,
     * so a config handed to that one never reaches RetroArch.
     */
    private static final String RETROARCH_FUTURE =
        "com.retroarch.browser.retroactivity.RetroActivityFuture";

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

    /**
     * Whether a runtime that can open this particular game is installed.
     *
     * <p>A DS game is served by WatermelonDS, so RetroArch being present
     * does not make it playable and vice versa.
     */
    public static boolean available(Context c, Game g) {
        if (Runtimes.isNintendoDs(g)) {
            return installed(c, WATERMELON_PKG);
        }
        return available(c, g.backend);
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
        // Resolved before anything looks for the backend's own app, because
        // a DS game is served by WatermelonDS under a different package. A
        // device with WatermelonDS and no RetroArch is the normal case once
        // the client has offered the DS runtime, and checking the backend
        // first told that device "no app installed for backend 'retroarch'"
        // -- a dead end, since availability correctly reported the DS
        // runtime present, so the button stayed on Play and never offered
        // to install anything.
        if (Runtimes.isNintendoDs(g) && installed(c, WATERMELON_PKG)) {
            launchWatermelon(c, g, payloadDir);
            return;
        }

        String pkg = installedPackage(c, g.backend);
        if (pkg == null) {
            throw new NotInstalled("no app installed for backend '" + g.backend + "'");
        }
        if ("retroarch".equals(g.backend)) {
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
        c.startActivity(intent, onBuiltIn());
    }

    /**
     * Where a runtime is started, rather than wherever this client happens
     * to be. Both observations behind this are from an AYN Thor, whose
     * launcher makes it easy to open an app on the external panel without
     * meaning to.
     *
     * <p>A dual-screen emulator keeps one DS screen in its own window and
     * presents the other onto a secondary display, so started on the
     * secondary display it has nowhere left to present and stacks both DS
     * screens into one window.
     *
     * <p>RetroArch is worse: on the secondary display its first-run
     * "grant access to Read External Storage" dialog does not render at
     * all, leaving a blank window over a permission the user cannot grant
     * and a runtime that can therefore never finish its setup.
     */
    private static Bundle onBuiltIn() {
        ActivityOptions o = ActivityOptions.makeBasic();
        o.setLaunchDisplayId(Display.DEFAULT_DISPLAY);
        return o.toBundle();
    }

    private static final String RETROARCH_MENU = "com.retroarch.browser.mainmenu.MainMenuActivity";

    /** Raised when a runtime needs its own first-run setup before it can be used. */
    public static final class NeedsSetup extends IOException {
        public NeedsSetup(String m) {
            super(m);
        }
    }

    /**
     * Open a runtime's own menu once, so it can create the directories it
     * only creates when launched.
     *
     * <p>RetroArch builds its private {@code cores/} directory on first
     * launch rather than at install time, and CoreSideloadActivity refuses
     * until it exists. Since this client now offers to install RetroArch,
     * a brand-new one is the normal case and the first game would
     * otherwise fail with an error the user cannot act on.
     *
     * <p>This does not wait for a timer, because what has to happen is not
     * a delay: on Android 13 a fresh RetroArch asks for storage and then
     * for media access, and only reaches its menu once both are answered.
     * An earlier version slept for nine seconds and hoped, which failed
     * every time on a real device. So the runtime is opened, the user
     * completes its setup, and they press Play again.
     *
     * @return true when the runtime was just opened for setup, meaning the
     *         caller should stop rather than hand off into an app that is
     *         still asking the user questions
     */
    private static String labelFor(String pkg) {
        return pkg.startsWith("com.retroarch") ? "RetroArch" : pkg;
    }

    private static boolean prime(Context c, String pkg) {
        File marker = new File(CoreInstaller.ROOT, "." + pkg + ".primed");
        if (marker.exists()) {
            return false;
        }
        try {
            Intent menu = new Intent();
            menu.setComponent(new ComponentName(pkg, RETROARCH_MENU));
            menu.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            Log.i(TAG, "priming " + pkg + ": opening it for its own first-run setup");
            c.startActivity(menu, onBuiltIn());
        } catch (Exception e) {
            Log.w(TAG, "could not open " + pkg + " for setup", e);
            return false;
        }
        // Recorded even though the user may abandon setup: a second
        // detour would be no more useful than the first, and the sideload
        // then fails with RetroArch's own message, which says exactly what
        // is wrong.
        try {
            if (!CoreInstaller.ROOT.isDirectory()) {
                CoreInstaller.ROOT.mkdirs();
            }
            new java.io.FileOutputStream(marker).close();
        } catch (IOException e) {
            Log.w(TAG, "cannot record priming of " + pkg, e);
        }
        return true;
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

        // RetroArch creates its private cores directory on its own first
        // launch, not at install time, and CoreSideloadActivity refuses
        // outright until it exists: "Destination directory doesn't exist
        // (/data/user/0/<pkg>/cores)". A freshly installed RetroArch --
        // which is now the common case, since this client offers to
        // install it -- therefore fails the first game with an error the
        // user cannot act on. So open its menu once and wait.
        if (prime(c, pkg)) {
            throw new NeedsSetup(labelFor(pkg) + " needs its own one-time setup."
                + " Answer its permission prompts until its menu appears, then press Play again.");
        }

        ApplicationInfo ra;
        try {
            ra = c.getPackageManager().getApplicationInfo(pkg, 0);
        } catch (PackageManager.NameNotFoundException e) {
            throw new NotInstalled("gone while launching: " + pkg);
        }

        // Shared storage is noexec, so RetroArch cannot load the core from
        // where we downloaded it. CoreSideloadActivity exists to copy it
        // into RetroArch's private cores directory, and that copy is the
        // only reason we still use it: it reads exactly LIBRETRO and ROM
        // and then builds its own intent around
        // UserPreferences.getDefaultConfigPath, so a game launched through
        // it runs under RetroArch's config and we cannot decide a setting.
        //
        // So the first game to use a core is launched through it anyway,
        // rather than as a separate install step. Sending it a core with
        // no ROM does copy the core, but RetroArch then tries to start
        // that core with no content and dies in it -- measured on an AYN
        // Thor: SIGSEGV in bsnes_libretro_android.so retro_set_environment,
        // taking the copy's own success message down with it. Playing the
        // game is what installs the core, and everything after that is
        // ours.
        File installed = new File(new File(ra.dataDir, "cores"), core.getName());
        if (!copyRecorded(c, pkg, core)) {
            sideload(c, pkg, core, rom);
            recordCopy(pkg, core);
            return;
        }

        // Everything RetroArch's own launcher passes, reproduced. DATADIR
        // and APK must be RetroArch's, not ours: they locate its bundled
        // assets, menu, overlays and autoconfig. SDCARD decides where its
        // saves, states and system directory default to, so omitting it
        // would silently relocate a user's existing data. IME is left out
        // deliberately -- it only renames a pad for three IME-based
        // gamepad bridges.
        String sdcard = Environment.getExternalStorageDirectory().getAbsolutePath();
        final Intent intent = new Intent();
        intent.setComponent(new ComponentName(pkg, RETROARCH_FUTURE));
        intent.putExtra("ROM", rom.getAbsolutePath());
        intent.putExtra("LIBRETRO", installed.getAbsolutePath());
        intent.putExtra("CONFIGFILE", RetroArchConfig.write(!hasGamepad()).getAbsolutePath());
        intent.putExtra("DATADIR", ra.dataDir);
        intent.putExtra("APK", ra.sourceDir);
        intent.putExtra("SDCARD", sdcard);
        intent.putExtra("EXTERNAL", sdcard + "/Android/data/" + pkg + "/files");
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        // Sent twice, for a reason specific to this activity. RetroArch is
        // singleInstance and reads its config once at startup, so a live
        // instance cannot be re-pointed: given a ROM that differs from the
        // one it started with, onNewIntent calls System.exit(0) and drops
        // the intent, and nothing relaunches it. A player who just quit a
        // different game and pressed Play on this one lands exactly there.
        // So the first intent may do nothing but kill the stale instance,
        // and the second one starts the game. With no instance running the
        // first starts it and the second is identical, which onNewIntent
        // answers with setIntent and no restart.
        Log.i(TAG, "handoff -> " + pkg + " core=" + installed + " rom=" + rom);
        c.startActivity(intent, onBuiltIn());

        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                Log.i(TAG, "handoff -> " + pkg + " second intent");
                try {
                    c.startActivity(intent, onBuiltIn());
                } catch (Exception e) {
                    Log.w(TAG, "second intent failed", e);
                }
            }
        }, SECOND_FIRE_MS);
    }

    /**
     * Play a game through RetroArch's own sideload entry, which copies the
     * core into its private directory on the way. Used for the first game
     * on each core, and only for the copy: this launch runs under
     * RetroArch's own config, so its touch overlay is drawn even on a
     * handheld whose controls make it useless. Every later launch of that
     * core goes through RetroActivityFuture with ours.
     */
    private static void sideload(final Context c, final String pkg, File core, File rom) {
        final Intent intent = new Intent();
        intent.setComponent(new ComponentName(pkg, RETROARCH_SIDELOAD));
        intent.putExtra("LIBRETRO", core.getAbsolutePath());
        intent.putExtra("ROM", rom.getAbsolutePath());
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        // Twice, as before: RetroArch creates its cores directory on its
        // own first launch and the sideload refuses until it exists, so an
        // attempt that lands too early has to be followed by one that does
        // not. The repeat costs a re-copy of a few MB.
        Log.i(TAG, "installing core into " + pkg + " by playing " + rom.getName());
        c.startActivity(intent, onBuiltIn());
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                try {
                    c.startActivity(intent, onBuiltIn());
                } catch (Exception e) {
                    Log.w(TAG, "second sideload intent failed", e);
                }
            }
        }, SECOND_FIRE_MS);
    }

    /**
     * Whether this core has already been copied into the runtime, recorded
     * on our side because its private cores directory is unreadable to us.
     *
     * <p>Keyed by the runtime's install time as well as the core, so a
     * reinstalled or updated RetroArch -- which takes its private data with
     * it -- is copied into again rather than launched against a core that
     * is no longer there.
     */
    private static File copyMarker(String pkg, File core) {
        return new File(CoreInstaller.ROOT, "." + pkg + "." + core.getName() + ".installed");
    }

    private static boolean copyRecorded(Context c, String pkg, File core) {
        return copyMarker(pkg, core).lastModified() >= installTime(c, pkg);
    }

    private static void recordCopy(String pkg, File core) {
        File marker = copyMarker(pkg, core);
        try {
            if (!CoreInstaller.ROOT.isDirectory()) {
                CoreInstaller.ROOT.mkdirs();
            }
            new java.io.FileOutputStream(marker).close();
        } catch (IOException e) {
            Log.w(TAG, "cannot record core install of " + core.getName(), e);
        }
    }

    /**
     * When the runtime was last installed or updated. Unknown means gone,
     * reported as a time no marker can satisfy so nothing is launched
     * against a core that cannot be there.
     */
    private static long installTime(Context c, String pkg) {
        try {
            return c.getPackageManager().getPackageInfo(pkg, 0).lastUpdateTime;
        } catch (PackageManager.NameNotFoundException e) {
            return Long.MAX_VALUE;
        }
    }

    /** Whether a physical pad is attached, which decides the touch overlay. */
    private static boolean hasGamepad() {
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice d = InputDevice.getDevice(id);
            if (d == null) {
                continue;
            }
            int s = d.getSources();
            if ((s & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
                || (s & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK) {
                return true;
            }
        }
        return false;
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
