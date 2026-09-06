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
import gaming.kraftwerk.strom.catalog.PadKeys;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.io.PrintWriter;

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
     * Azahar, for 3DS games. Its launch contract is an explicit
     * ACTION_VIEW at EmulationActivity with the ROM as intent data --
     * there is no custom action to name, unlike WatermelonDS. The
     * component is given explicitly, so the activity's own intent-filter
     * (mimeType application/octet-stream, scheme content) does not have to
     * be matched.
     *
     * <p>It renders the 3DS's two screens onto two physical displays
     * through android.app.Presentation when its secondary-display setting
     * is on, which is chosen in Azahar's settings: no intent extra
     * selects it, so a two-panel handheld needs that switch flipped once
     * by hand.
     */
    private static final String AZAHAR_PKG = "org.azahar_emu.azahar";
    private static final String AZAHAR_ACTIVITY = "org.citra.citra_emu.activities.EmulationActivity";

    /**
     * GameNative's only external surface: an action on its exported
     * MainActivity. There is no result code and no broadcast back, so a
     * caller can observe "GameNative came to the foreground" and nothing
     * more -- see the launch method for what that costs us.
     */
    /**
     * GameNative's launch action is derived from its own application id
     * (`"${BuildConfig.APPLICATION_ID}.LAUNCH_GAME"`), so a build with a
     * suffixed id listens on a different action. Deriving ours the same way
     * means a fork, a `.gold` build or a locally built test build all work
     * without a second code path -- and it is what let us test a patched
     * build side by side with the released one.
     */
    private static String gamenativeLaunchAction(String pkg) {
        return pkg + ".LAUNCH_GAME";
    }

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
            // The released build, then variants of it: a `.fork` test build
            // sits beside the release rather than replacing it, because the
            // two cannot share a signature and uninstalling the release
            // takes every configured container with it. Order matters --
            // the release wins when both are installed.
            candidates = new String[] { "app.gamenative", "app.gamenative.fork" };
        } else if (backend.equals("dolphin")) {
            candidates = new String[] { "org.dolphinemu.dolphinemu" };
        } else if (backend.equals("azahar")) {
            // Only the vanilla artifact. The Play flavour carries the
            // legacy id io.github.lime3ds.android AND skips the code that
            // turns an incoming content:// URI into a file descriptor, so
            // accepting it here would report a runtime that cannot open
            // anything this client hands it.
            candidates = new String[] { AZAHAR_PKG };
        } else {
            return null;
        }
        PackageManager pm = c.getPackageManager();
        for (String p : candidates) {
            try {
                pm.getPackageInfo(p, 0);
            } catch (PackageManager.NameNotFoundException e) {
                continue;
            }
            // Installed is not the same as able to run it. A package that is
            // present but disabled still answers getPackageInfo, and handing
            // it an intent then dies with ActivityNotFoundException -- which
            // is what happens when two GameNative builds are installed and
            // one is switched off. Ask whether the launch would resolve
            // instead, and fall through to the next candidate when it would
            // not. Backends whose launch is not a package-scoped action
            // (retroarch's sideload dance, azahar) keep the presence answer.
            if (backend.equals("gamenative")) {
                Intent probe = new Intent(gamenativeLaunchAction(p)).setPackage(p);
                if (pm.resolveActivity(probe, 0) == null) {
                    continue;
                }
            }
            return p;
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
        if ("azahar".equals(g.backend)) {
            launchAzahar(c, pkg, g, payloadDir);
            return;
        }
        if ("retroarch".equals(g.backend)) {
            launchRetroArch(c, pkg, g, payloadDir);
            return;
        }
        if ("gamenative".equals(g.backend)) {
            launchGameNative(c, pkg, g, payloadDir);
            return;
        }
        // Dolphin is described in docs/android.md, but its decisive fact is
        // still marked device-only there: the intent shape has never been
        // measured against a running app. Inventing one here would produce a
        // silent no-op on a phone, which is worse than a refusal that names
        // what is missing.
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
     * Hand a 3DS dump to Azahar.
     *
     * <p>The ROM travels as a path in the {@code SelectedGame} extra, with
     * a {@code !} in front of it, and not as the intent's data URI the way
     * the DS handoff does. That prefix is Azahar's own marker for "this is
     * a filesystem path, not a document": it skips the branch that turns an
     * incoming URI into a file descriptor, and reaches the loader as a path
     * Azahar opens itself, which it can do because its setup takes an
     * all-files permission.
     *
     * <p>Chosen over a {@code content:} URI because a URI has to be
     * grantable to be useful, and this client can only grant one for a file
     * it created: a payload placed by anything else -- staged by hand, or
     * left by an earlier install -- fails with "UID ... does not have
     * permission to content://media/...". A path has no such condition, so
     * whoever put the bytes there, the launch works. It is also a string
     * extra rather than a Uri, so no {@code file:} URI is ever handed to
     * another process and FileUriExposedException cannot arise.
     *
     * <p>Its action is the plain ACTION_VIEW rather than a private one,
     * and the component is set explicitly so the activity's declared
     * mimeType does not have to be matched.
     *
     * <p>Sent once. RetroArch needs a second intent because its sideload
     * entry tears down the activity it just started; nothing here does
     * that.
     */
    private static void launchAzahar(Context c, String pkg, Game g, File payloadDir)
        throws IOException {
        File rom = romIn(payloadDir, g.launchTarget);
        if (rom == null) {
            throw new IOException("launch target '" + g.launchTarget
                + "' not found under " + payloadDir);
        }

        // Azahar's first run is a wizard, and it is not optional: it takes
        // an all-files permission and a folder for its data, and until it
        // has them its user directory does not exist. Handing
        // EmulationActivity a ROM before that does not fail gracefully, it
        // crashes Azahar -- RuntimeException out of
        // DirectoryInitialization.getUserDirectory, measured on an AYN
        // Thor. So open its own UI once and say what it will ask for, the
        // same detour RetroArch needs.
        //
        // Any folder will do. Azahar opens the system picker with no
        // initial location (PermissionsHandler.compatibleSelectDirectory
        // passes null on Android 11+), so steering the choice would mean
        // telling the player exactly where to tap; the folder is found
        // afterwards instead. See AzaharConfig.
        if (prime(c, pkg)) {
            // Two of Azahar's own settings are named here because they are
            // the two a handheld needs and neither can be set from outside:
            // the host-key mapping and the on-screen overlay both live in
            // Azahar's default SharedPreferences, inside its private data
            // directory, where no permission reaches. Unmapped is not a
            // degraded state but a dead one -- getButtonSet returns an
            // empty set, so a physical pad does literally nothing while the
            // touch overlay still works, which is a confusing way to find
            // out. Auto-map is one action in its Controls settings.
            throw new NeedsSetup("Azahar needs its own one-time setup."
                + " Give it filesystem access, pick any folder for its data,"
                + " and finish its welcome screens. Then, in its settings,"
                + " use Controls > Auto-map so the gamepad works, and turn the"
                + " on-screen overlay off. Then press Play again.");
        }

        // Only on a device that has a second panel, and only once: asking
        // for all-files access buys exactly one thing, a screen on each
        // panel instead of both in one window, so it is asked for where
        // that is true and skipped everywhere else. Declining is a fine
        // outcome -- the game still runs under Azahar's own layout -- which
        // is why this is asked once and never again.
        if (AzaharConfig.secondDisplay(c) && !AzaharConfig.canWrite() && askOnce(c, pkg, pkg)) {
            c.startActivity(AzaharConfig.grantIntent(c));
            throw new NeedsSetup("For a screen on each panel, Strom needs"
                + " all-files access: it writes the two-screen setting into"
                + " Azahar's own config, wherever you put it. Allow it and press"
                + " Play again, or just press Play again to use Azahar's layout.");
        }
        AzaharConfig.apply(c);
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setComponent(new ComponentName(pkg, AZAHAR_ACTIVITY));
        intent.putExtra("SelectedGame", "!" + rom.getAbsolutePath());
        intent.putExtra("SelectedTitle", g.title());
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        Log.i(TAG, "handoff -> " + pkg + " (3ds) rom=" + rom);
        c.startActivity(intent, onBuiltIn());
    }

    /**
     * Hand a Windows game to GameNative, which runs it under wine on box64.
     *
     * <p>Three couplings, and only the last is an interface GameNative
     * advertises:
     *
     * <ol>
     *   <li>the tree sits in its own folder on public storage,
     *   <li>a {@code .gamenative} file in it fixes the id, so ours is
     *       deterministic instead of a hash of a path,
     *   <li>the user registers that folder once, inside GameNative -- its
     *       custom-game library IS the list of registered folders, held in
     *       its own private preferences, and nothing exported writes to it,
     *   <li>the launch intent, which names the id and nothing else.
     * </ol>
     *
     * <p><b>Deliberately no container_config, and this is the whole
     * design.</b> Sending one looks obvious -- it is how you would set the
     * executable and point the {@code A:} drive at the game -- and it
     * cannot be used on any current Adreno device. Measured on an AYN Thor
     * against GameNative 1.1.1, then confirmed in its source:
     *
     * <ul>
     *   <li>Its intent parser rebuilds the whole container record from the
     *       JSON, and {@code wineVersion} is not one of the keys it reads.
     *       So the record is completed with the class default,
     *       {@code wine-9.2-x86_64}, and applying it overwrites the wine
     *       build unconditionally. Every Adreno device is configured for
     *       {@code proton-9.0-arm64ec} instead, and that build is the one
     *       actually installed, so the launch then looks for a wine that
     *       was never there: {@code [BOX64] Error: File is not found.
     *       (wine)}, guest status 255, a black screen. The container's own
     *       stored wine build is left correct, which is what makes this
     *       look mysterious -- only the launch is poisoned.
     *   <li>Without a config, the drive layout is the one GameNative
     *       computed when it created the container: {@code A:} is the
     *       folder the user registered. So the folder to register is this
     *       game's own, not a shared parent -- a parent would put the
     *       executable one level below {@code A:\}, where its own
     *       auto-detect has to guess, and FF8 alone ships nine
     *       {@code .exe} files.
     * </ul>
     *
     * <p>Which leaves the executable. With no config we cannot send it, and
     * auto-detect refuses whenever a tree has more than one candidate, so
     * the player sets it once in GameNative's own container settings -- the
     * exact thing GameNative's own error message asks for. Named in the
     * setup message below, because a player cannot guess
     * {@code strom-ff8-supervisor.exe}.
     *
     * <p>Nothing comes back either way: no result code, no broadcast, and a
     * missing executable is not an error to GameNative -- it boots its
     * bundled file manager. So this reports "handed off", never "running".
     */
    private static void launchGameNative(Context c, String pkg, Game g, File payloadDir)
        throws IOException {
        if (!payloadDir.isDirectory()) {
            throw new IOException("payload directory " + payloadDir + " is missing");
        }
        int appId = gamenativeId(payloadDir);

        // The pad-to-key profile, when the manifest declares one. A runtime
        // that accepts the registration intent gets it sent and imported;
        // it is also written beside the game as GameNative's own `.icp`,
        // which is this client's record of what it last sent (a change
        // re-registers) and a readable statement of the mapping. Stock
        // GameNative cannot import it -- its InputControlsManager has an
        // importProfile() that no screen calls -- so a stock install is
        // told the bindings to set by hand instead.
        String profileName = null;
        String profileJson = null;
        boolean profileChanged = false;
        if (PadKeys.any(g.padKeys)) {
            profileName = "strom: " + g.slug;
            profileJson = PadKeys.profileJson(0, profileName, g.padKeys);
            profileChanged = writeIfChanged(new File(payloadDir, PROFILE_FILE), profileJson);
        }

        // A runtime carrying the registration intent (our fork, and
        // upstream once it lands) registers the folder itself; every other
        // build needs the player to do it once, in its own UI.
        Intent register = new Intent(pkg + ".ADD_CUSTOM_GAME_FOLDER").setPackage(pkg);
        boolean registers = c.getPackageManager().resolveActivity(register, 0) != null;
        if (registers) {
            // Only when there is something new to say: registration is
            // idempotent but not free -- it cold-starts GameNative, and a
            // launch sent into that startup is dropped (measured: the
            // launch parsed, "Emitting ExternalGameLaunch", no session).
            // So register on the first run and whenever the profile
            // changed, wait out the startup, and otherwise send the launch
            // alone.
            // "Registered" is a fact about this install of GameNative, not
            // about the folder: its folder list dies with a reinstall, so
            // the record is the per-install kind (askOnce), not the
            // .gamenative file beside the game, which is GameNative's own
            // id record and stays put across installs.
            boolean firstTime = askOnce(c, pkg, pkg + "-registered-" + g.slug);
            if (firstTime || profileChanged) {
                register.putExtra("folder", payloadDir.getAbsolutePath());
                if (profileJson != null) {
                    register.putExtra("controls_profile", profileJson);
                }
                register.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                c.startActivity(register, onBuiltIn());
                Log.i(TAG, "registered " + payloadDir + " with " + pkg
                    + (profileJson == null ? "" : " + controls profile"));
                try {
                    Thread.sleep(8000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            // The one setting no intent can carry, said once per install
            // rather than per game: GameNative keeps the last chosen
            // emulator as the default for every container it creates.
            if (askOnce(c, pkg, pkg + "-emulator")) {
                throw new NeedsSetup("Once, in GameNative: open any game's"
                    + " container settings and under Emulation set the emulator"
                    + " to Box64. Its default, FEXCore, cannot run 32-bit games"
                    + " (they exit within a second, with no message), and"
                    + " GameNative remembers the choice for every game after."
                    + " Then press Play again.");
            }
        }

        // Asked once per GAME, not once per runtime: the folder to register
        // is this game's own, so a second gamenative game needs its own
        // instruction rather than silently inheriting the first one's
        // marker and landing in GameNative's "not installed" dialog. We
        // cannot read the answer either way -- the folder list lives in its
        // private preferences.
        if (!registers && askOnce(c, pkg, pkg + "-" + g.slug)) {
            // Everything the intent cannot carry, said once and in full. Each
            // of these IS in the manifest and IS computable -- they travel in
            // the same container_config that would overwrite the wine build,
            // so naming them is all we can do. Measured consequences of
            // leaving one out: a 720p container on a 1080p panel renders the
            // game in a scaled, decorated window with black margins, and a
            // D3D12 game stops at "Failed to create D3D12 Device".
            //
            // The emulator comes first because it is the one that kills
            // silently: GameNative's default, FEXCore, faults inside its own
            // wow64 layer the moment a 32-bit executable starts (a one-page
            // stack, err:virtual:virtual_setup_exception), so every 32-bit
            // game runs for a second and vanishes with no dialog. Box64 runs
            // the same binaries, 64-bit ones included, and GameNative keeps
            // the last chosen emulator as the default for every container it
            // creates afterwards -- so this is one setting, not one per game.
            throw new NeedsSetup("GameNative needs this folder added to its"
                + " library, once: " + payloadDir.getAbsolutePath()
                + ". Open GameNative, add a game folder, pick that one."
                + " In that entry's container settings: under Emulation set"
                + " the emulator to Box64 (FEXCore cannot run 32-bit games;"
                + " GameNative remembers this for later games), set Screen"
                + " Size to your screen, set the executable path to "
                + g.executablePath + " if it says the executable could not"
                + " be auto-selected, and set DX Wrapper to VKD3D if the game"
                + " needs Direct3D 12."
                + (profileJson == null ? "" : " This game reads the keyboard,"
                    + " not a pad: in Input Controls, make a profile for it"
                    + " binding " + PadKeys.describe(g.padKeys) + ".")
                + " Then press Play again.");
        }

        Intent intent = new Intent(gamenativeLaunchAction(pkg));
        intent.setPackage(pkg);
        intent.putExtra("app_id", appId);
        // Uppercased and then matched against an enum; anything it does not
        // recognise silently becomes STEAM, which would look for a game we
        // never installed.
        intent.putExtra("game_source", "CUSTOM_GAME");
        if (registers && profileName != null) {
            intent.putExtra("controls_profile", profileName);
        }
        // A container_config, but only for a runtime that resolves the
        // registration action: that build's parser merges over the
        // container's stored record, so the wine build survives. Upstream's
        // rebuilds the record from the JSON and would replace it with a
        // wine that is not installed (see the class comment). What it
        // carries is exactly what the setup message otherwise asks for by
        // hand, plus one thing for a pad-to-keys game: winhandler's
        // "Standard (Old Gamepads)" mapper emulates a keyboard from the
        // pad on top of the profile's keys -- FF8 saw Shift+Left on every
        // stick move, which FFNx takes as "cycle the aspect ratio" -- and
        // the XInput mapper does not.
        String config = null;
        if (registers) {
            StringBuilder sb = new StringBuilder("{\"executablePath\":")
                .append(jsonString(g.executablePath))
                .append(",\"dxwrapper\":").append(jsonString(g.dxwrapper));
            // The game's own size when it declares one, else the panel's.
            // Omitting the key does not get the panel: GameNative's
            // "detection" only buckets the aspect ratio and every 16:9
            // device lands on its 1280x720 constant, which on a 1080p
            // panel is a scaled, decorated window with black margins
            // (measured twice: FF8, then ANIMAL WELL through the stock
            // path). A size from the catalog is wrong the other way round,
            // it is the recipe author's panel, not the player's.
            sb.append(",\"screenSize\":")
                .append(jsonString(g.screenSize != null ? g.screenSize : panelSize(c)));
            if (!g.execArgs.isEmpty()) {
                sb.append(",\"execArgs\":").append(jsonString(g.execArgs));
            }
            if (profileName != null) {
                sb.append(",\"dinputMapperType\":2");
            }
            config = sb.append('}').toString();
            intent.putExtra("container_config", config);
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        Log.i(TAG, "handoff -> " + pkg + " (windows) appId=" + appId
            + " dir=" + payloadDir + " exe=" + g.executablePath
            + (profileName == null ? "" : " pad->keys profile '" + profileName + "'")
            + (config == null
                ? " (no container_config: it would overwrite the wine build)"
                : " config=" + config));
        c.startActivity(intent, onBuiltIn());
    }

    private static String jsonString(String s) {
        StringBuilder sb = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch == '"' || ch == '\\') {
                sb.append('\\');
            }
            sb.append(ch);
        }
        return sb.append('"').toString();
    }

    /** GameNative's own profile format, left beside the game for a stock install to import. */
    static final String PROFILE_FILE = "strom-controls.icp";

    /** Writes {@code content} unless the file already holds exactly it; true when written. */
    private static boolean writeIfChanged(File f, String content) throws IOException {
        byte[] want = content.getBytes("UTF-8");
        if (f.isFile() && f.length() == want.length) {
            byte[] have = new byte[want.length];
            java.io.FileInputStream in = new java.io.FileInputStream(f);
            try {
                int off = 0;
                while (off < have.length) {
                    int n = in.read(have, off, have.length - off);
                    if (n < 0) {
                        break;
                    }
                    off += n;
                }
            } finally {
                in.close();
            }
            if (java.util.Arrays.equals(have, want)) {
                return false;
            }
        }
        java.io.FileOutputStream out = new java.io.FileOutputStream(f);
        try {
            out.write(want);
        } finally {
            out.close();
        }
        return true;
    }

    /**
     * The id GameNative will use for the registered folder, pinned by
     * writing its own metadata file.
     *
     * <p>Without the file it derives one from the folder path's hash, which
     * we could recompute -- but that ties us to another app's hashing and
     * to Java's String.hashCode staying what it is. Writing the file makes
     * the id ours and survives every rescan, because a present positive
     * appId is returned unchanged. Must be positive: the intent parser
     * rejects anything else and reports it only in its own UI.
     */
    private static int gamenativeId(File parent) throws IOException {
        File marker = new File(parent, ".gamenative");
        int id = Math.abs(parent.getAbsolutePath().hashCode());
        if (id == 0) {
            id = 1;
        }
        if (marker.isFile()) {
            BufferedReader r = new BufferedReader(new FileReader(marker));
            try {
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = r.readLine()) != null) {
                    sb.append(line);
                }
                int at = sb.indexOf("\"appId\"");
                if (at >= 0) {
                    String tail = sb.substring(at + 7).replace(":", " ");
                    java.util.Scanner sc = new java.util.Scanner(tail);
                    if (sc.hasNextInt()) {
                        int found = sc.nextInt();
                        if (found > 0) {
                            return found;
                        }
                    }
                }
            } finally {
                r.close();
            }
        }
        if (!parent.isDirectory() && !parent.mkdirs()) {
            throw new IOException("cannot create " + parent);
        }
        PrintWriter w = new PrintWriter(marker, "UTF-8");
        try {
            w.print("{\"appId\": " + id + "}");
        } finally {
            w.close();
        }
        return id;
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
    /**
     * Azahar's own launcher activity, opened so it can run its first-run
     * wizard. Handing EmulationActivity a ROM before that has happened
     * does not merely fail, it crashes Azahar:
     * {@code RuntimeException ... DirectoryInitialization.getUserDirectory},
     * because its user directory is a folder the user must still grant.
     */
    private static final String AZAHAR_MAIN = "org.citra.citra_emu.ui.main.MainActivity";

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
        if (pkg.startsWith("com.retroarch")) {
            return "RetroArch";
        }
        if (pkg.equals(AZAHAR_PKG)) {
            return "Azahar";
        }
        return pkg;
    }

    /** The activity to open so a runtime performs its own first-run setup. */
    private static String setupActivity(String pkg) {
        return pkg.equals(AZAHAR_PKG) ? AZAHAR_MAIN : RETROARCH_MENU;
    }

    /**
     * True once per install of the runtime app, then never again. Records
     * that we have asked the player for something, so a request they
     * declined does not reappear on every launch of every game.
     *
     * <p>Per install, not forever: everything asked through here is state
     * inside the runtime app (a registered folder, the emulator choice,
     * a permission), and a reinstall of that app -- replacing upstream
     * GameNative with ours, say -- starts it empty again while a marker
     * written for the old install would say "already done". Measured:
     * GameNative reinstalled, launch sent alone, its "Game Not Installed"
     * dialog. So a marker older than the app's install counts as absent.
     */
    private static boolean askOnce(Context c, String pkg, String what) {
        File marker = new File(CoreInstaller.ROOT, "." + what + ".asked");
        if (marker.exists() && marker.lastModified() >= installedAt(c, pkg)) {
            return false;
        }
        try {
            if (!CoreInstaller.ROOT.isDirectory()) {
                CoreInstaller.ROOT.mkdirs();
            }
            new java.io.FileOutputStream(marker).close();
            marker.setLastModified(System.currentTimeMillis());
        } catch (IOException e) {
            Log.w(TAG, "cannot record the request for " + what, e);
        }
        return true;
    }

    /**
     * When the runtime app was installed, as a wall-clock millisecond;
     * a reinstall moves it. Zero when the app is not installed, so every
     * marker then reads as current.
     */
    static long installedAt(Context c, String pkg) {
        try {
            return c.getPackageManager().getPackageInfo(pkg, 0).firstInstallTime;
        } catch (PackageManager.NameNotFoundException e) {
            return 0;
        }
    }

    /**
     * The default display's physical size as GameNative's "WxH", landscape
     * whichever way the device is held: the container's desktop fills the
     * panel only when it is the panel's own pixel count.
     */
    static String panelSize(Context c) {
        android.hardware.display.DisplayManager dm =
            (android.hardware.display.DisplayManager) c.getSystemService(Context.DISPLAY_SERVICE);
        Display d = dm == null ? null : dm.getDisplay(Display.DEFAULT_DISPLAY);
        if (d == null) {
            return "1920x1080";
        }
        Display.Mode m = d.getMode();
        int w = Math.max(m.getPhysicalWidth(), m.getPhysicalHeight());
        int h = Math.min(m.getPhysicalWidth(), m.getPhysicalHeight());
        return w + "x" + h;
    }

    private static boolean prime(Context c, String pkg) {
        File marker = new File(CoreInstaller.ROOT, "." + pkg + ".primed");
        if (marker.exists()) {
            return false;
        }
        try {
            Intent menu = new Intent();
            menu.setComponent(new ComponentName(pkg, setupActivity(pkg)));
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
    private static void sideload(Context c, String pkg, File core, File rom) {
        Intent intent = new Intent();
        intent.setComponent(new ComponentName(pkg, RETROARCH_SIDELOAD));
        intent.putExtra("LIBRETRO", core.getAbsolutePath());
        intent.putExtra("ROM", rom.getAbsolutePath());
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        // Exactly once. An earlier version sent this twice, six seconds
        // apart, to survive a cores directory that did not exist yet --
        // priming the runtime handles that now, and the repeat was doing
        // real damage: the copy overwrites the .so in place, so the second
        // one rewrote a core the game launched by the first had already
        // loaded. Reported as Super Mario 64 and A Link to the Past
        // quitting a few seconds in; the crash is in the core, six seconds
        // after it started.
        Log.i(TAG, "installing core into " + pkg + " by playing " + rom.getName());
        c.startActivity(intent, onBuiltIn());
    }

    /**
     * Whether this core is known to be in place inside the runtime,
     * recorded on our side because its private cores directory is
     * unreadable to us.
     *
     * <p>Keyed by the runtime's install time as well as the core, so a
     * reinstalled or updated RetroArch -- which takes its private data with
     * it -- is copied into again rather than launched against a core that
     * is no longer there.
     *
     * <p>The marker records when the copy should be <em>finished</em>, not
     * when it was started, and that distinction is not academic: a 67 MB
     * fbneo copy was still in flight when a second Play took the launch
     * path that trusts it, and RetroArch got a half-written core --
     * {@code linker: has invalid shdr offset/size: 66956040/1792}, then a
     * black screen. Being early costs a corrupt core; being late costs one
     * more launch through the sideload path, which merely draws the
     * overlay again. So the estimate is deliberately pessimistic.
     */
    private static File copyMarker(String pkg, File core) {
        return new File(CoreInstaller.ROOT, "." + pkg + "." + core.getName() + ".installed");
    }

    private static boolean copyRecorded(Context c, String pkg, File core) {
        File marker = copyMarker(pkg, core);
        if (marker.lastModified() < installTime(c, pkg)) {
            return false;
        }
        return readyAt(marker) <= System.currentTimeMillis();
    }

    /**
     * When the copy this marker stands for can be believed.
     *
     * <p>A marker with nothing in it was written by a version that had no
     * notion of a copy still being in flight, and meant "this core is
     * installed" outright. Treated as such rather than as corrupt: reading
     * it as never-ready sends every one of those cores back through the
     * copy path on every launch, which is how a re-copy came to land on
     * top of a running game.
     */
    private static long readyAt(File marker) {
        try {
            BufferedReader r = new BufferedReader(new FileReader(marker));
            try {
                String s = r.readLine();
                if (s == null || s.trim().isEmpty()) {
                    return 0L;
                }
                return Long.parseLong(s.trim());
            } finally {
                r.close();
            }
        } catch (IOException e) {
            return Long.MAX_VALUE;
        } catch (NumberFormatException e) {
            return 0L;
        }
    }

    /**
     * Note that a copy of this core is under way, and when to believe it.
     * One mebibyte per second is far below what the device manages; the
     * point is a bound that a slow copy cannot beat, not an estimate.
     */
    private static void recordCopy(String pkg, File core) {
        long ready = System.currentTimeMillis() + SECOND_FIRE_MS
            + (core.length() / 1024) + 5000L;
        File marker = copyMarker(pkg, core);
        try {
            if (!CoreInstaller.ROOT.isDirectory()) {
                CoreInstaller.ROOT.mkdirs();
            }
            PrintWriter w = new PrintWriter(marker, "UTF-8");
            try {
                w.println(ready);
            } finally {
                w.close();
            }
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
