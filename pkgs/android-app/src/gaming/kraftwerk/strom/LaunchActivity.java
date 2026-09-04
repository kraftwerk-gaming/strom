package gaming.kraftwerk.strom;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;

import gaming.kraftwerk.strom.catalog.Catalog;
import gaming.kraftwerk.strom.catalog.Game;
import gaming.kraftwerk.strom.ipfs.Fetcher;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Launch one game without touching the UI.
 *
 * <p>Exists because driving the on-screen list is the wrong interface for
 * two real callers: a test loop (typing a URL into a phone keyboard over
 * adb is slow and misses), and a frontend that already has its own library
 * screen and only wants a game started.
 *
 * <pre>
 * adb shell am start -n gaming.kraftwerk.strom/.LaunchActivity \
 *   --es remote http://10.0.0.5:8124 \
 *   --es slug animal-well \
 *   --es gateway http://10.0.0.5:8081 \
 *   --es options 'music=orchestral,voices=true'
 * </pre>
 *
 * <p>`remote` defaults to the one the list screen last used, else the
 * public seed the app ships with, so the common case is just `--es slug`.
 * `gateway` is optional and sets the private IPFS
 * gateway for this process. `options` is a comma-separated list of
 * `key=value` picks, applied over the manifest defaults for this launch
 * only -- it does not overwrite what a player chose on screen.
 *
 * <p>It runs the same {@link Launch} pipeline the list screen does, so a
 * launch driven this way proves the path a player takes rather than a
 * parallel one. Progress goes to logcat under the `strom` tag and the
 * outcome sets the activity result, so a caller can wait for it:
 * RESULT_OK for launched, RESULT_CANCELED with a `message` extra otherwise.
 */
public final class LaunchActivity extends Activity {
    private static final String TAG = "strom";
    private static final String PREFS = "strom";
    private static final String PREF_CATALOG = "catalog-url";
    private static final String PREF_GATEWAY = "private-gateway";

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);

        Intent in = getIntent();
        final String slug = in.getStringExtra("slug");
        String remote = in.getStringExtra("remote");
        String gateway = in.getStringExtra("gateway");
        final String options = in.getStringExtra("options");

        // Same resolution as the grid: the intent's remote, else whatever
        // the settings screen holds, else the public seed. An empty remote
        // used to fall through here, so every automated launch had to
        // repeat the URL that the app already knows.
        if (remote == null || remote.trim().isEmpty()) {
            remote = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getString(PREF_CATALOG, MainActivity.DEFAULT_CATALOG);
        }
        if (remote.trim().isEmpty()) {
            remote = MainActivity.DEFAULT_CATALOG;
        }
        if (gateway == null || gateway.trim().isEmpty()) {
            gateway = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getString(PREF_GATEWAY, "");
        }
        Fetcher.setPrivateGateway(gateway);

        if (slug == null || slug.trim().isEmpty()) {
            finishWith(false, "no slug given");
            return;
        }

        final String base = remote.trim();
        new Thread(new Runnable() {
            @Override
            public void run() {
                Game game = null;
                try {
                    List<Game> games = Catalog.load(base);
                    for (Game g : games) {
                        if (slug.equals(g.slug)) {
                            game = g;
                            break;
                        }
                    }
                } catch (Exception e) {
                    Log.w(TAG, "catalog " + base + " failed", e);
                    finishWith(false, "catalog failed: " + e);
                    return;
                }
                if (game == null) {
                    finishWith(false, "no game '" + slug + "' in " + base);
                    return;
                }
                Log.i(TAG, "automated launch: " + slug + " from " + base);
                Launch.Outcome out = Launch.run(LaunchActivity.this, game,
                    parse(options), new Launch.Progress() {
                        @Override
                        public void say(String message) {
                            Log.i(TAG, "launch " + slug + ": " + message);
                        }
                    });
                finishWith(out.result == Launch.Result.LAUNCHED, out.message);
            }
        }).start();
    }

    /** `key=value,key=value`; anything unparseable is ignored, loudly. */
    private static Map<String, String> parse(String options) {
        Map<String, String> picks = new LinkedHashMap<String, String>();
        if (options == null || options.trim().isEmpty()) {
            return picks;
        }
        for (String part : options.split(",")) {
            int eq = part.indexOf('=');
            if (eq <= 0) {
                Log.w(TAG, "ignoring option '" + part + "': expected key=value");
                continue;
            }
            picks.put(part.substring(0, eq).trim(), part.substring(eq + 1).trim());
        }
        return picks;
    }

    private void finishWith(final boolean ok, final String message) {
        Log.i(TAG, "automated launch " + (ok ? "ok" : "failed") + ": " + message);
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                // Said on screen too: a NeedsSetup instruction is useless in
                // logcat when the person who needs it is holding the device.
                if (!ok) {
                    Toast.makeText(LaunchActivity.this, message, Toast.LENGTH_LONG).show();
                }
                Intent result = new Intent();
                result.putExtra("message", message);
                setResult(ok ? RESULT_OK : RESULT_CANCELED, result);
                finish();
            }
        });
    }
}
