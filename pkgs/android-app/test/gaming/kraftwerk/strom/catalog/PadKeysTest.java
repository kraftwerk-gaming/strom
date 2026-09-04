package gaming.kraftwerk.strom.catalog;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The manifest's pad mapping rendered as a GameNative profile. Every case
 * here is one that, wrong, leaves a button dead on a handheld with no
 * error anywhere: the key codes GameNative binds by, the vocabulary it
 * accepts, and the one axis whose sign it inverts.
 */
public final class PadKeysTest {
    private static int failures = 0;

    public static void main(String[] args) throws Exception {
        buttonsBindByAndroidKeyCode();
        sticksUseGameNativesPseudoCodesWithYInverted();
        dpadArrivesAsDpadKeyCodes();
        keysCoverLettersDigitsAndNamedKeys();
        aTypoFailsLoudly();
        theProfileIsGameNativesFormat();
        emptyMeansXInput();

        if (failures > 0) {
            System.err.println(failures + " test(s) failed");
            System.exit(1);
        }
        System.out.println("all pad profile tests passed");
    }

    private static Map<String, String> map(String... kv) {
        Map<String, String> m = new LinkedHashMap<String, String>();
        for (int i = 0; i < kv.length; i += 2) {
            m.put(kv[i], kv[i + 1]);
        }
        return m;
    }

    private static PadKeys.Bind find(List<PadKeys.Bind> binds, int keyCode) {
        for (PadKeys.Bind b : binds) {
            if (b.keyCode == keyCode) {
                return b;
            }
        }
        return null;
    }

    private static void buttonsBindByAndroidKeyCode() {
        // FF8's real mapping, as its own Keyboard screen lists it.
        List<PadKeys.Bind> b = PadKeys.bindings(map(
            "a", "X", "b", "C", "y", "V", "x", "S",
            "l1", "H", "r1", "G", "l2", "F", "r2", "J",
            "start", "A", "select", "D"));
        check("A is KEYCODE_BUTTON_A (96)", find(b, 96) != null && find(b, 96).binding.equals("KEY_X"));
        check("B is 97", find(b, 97).binding.equals("KEY_C"));
        check("X is 99, Y is 100 (not the other way round)",
            find(b, 99).binding.equals("KEY_S") && find(b, 100).binding.equals("KEY_V"));
        check("shoulders 102/103, triggers 104/105",
            find(b, 102).binding.equals("KEY_H") && find(b, 103).binding.equals("KEY_G")
                && find(b, 104).binding.equals("KEY_F") && find(b, 105).binding.equals("KEY_J"));
        check("start 108, select 109",
            find(b, 108).binding.equals("KEY_A") && find(b, 109).binding.equals("KEY_D"));
        check("ten buttons, ten bindings", b.size() == 10);
    }

    private static void sticksUseGameNativesPseudoCodesWithYInverted() {
        List<PadKeys.Bind> b = PadKeys.bindings(map("leftStick", "arrows"));
        check("left is -1, right is -2",
            find(b, -1).binding.equals("KEY_LEFT") && find(b, -2).binding.equals("KEY_RIGHT"));
        // getKeyCodeForAxis(AXIS_Y, +) yields AXIS_Y_NEGATIVE (-3) while
        // Android's +Y is stick DOWN. Measured: the other way round, the
        // stick moved the FF8 cursor backwards.
        check("-3 carries DOWN, -4 carries UP",
            find(b, -3).binding.equals("KEY_DOWN") && find(b, -4).binding.equals("KEY_UP"));
        List<PadKeys.Bind> r = PadKeys.bindings(map("rightStick", "wasd"));
        check("right stick is -5..-8 with the same inversion",
            find(r, -5).binding.equals("KEY_A") && find(r, -6).binding.equals("KEY_D")
                && find(r, -7).binding.equals("KEY_S") && find(r, -8).binding.equals("KEY_W"));
    }

    private static void dpadArrivesAsDpadKeyCodes() {
        List<PadKeys.Bind> b = PadKeys.bindings(map("dpad", "arrows"));
        check("hat becomes KEYCODE_DPAD_UP..RIGHT (19..22)",
            find(b, 19).binding.equals("KEY_UP") && find(b, 20).binding.equals("KEY_DOWN")
                && find(b, 21).binding.equals("KEY_LEFT") && find(b, 22).binding.equals("KEY_RIGHT"));
    }

    private static void keysCoverLettersDigitsAndNamedKeys() {
        List<PadKeys.Bind> b = PadKeys.bindings(map("a", "x", "b", "5", "x", "enter", "y", "Esc"));
        check("a lower-case letter is upper-cased", find(b, 96).binding.equals("KEY_X"));
        check("a digit", find(b, 97).binding.equals("KEY_5"));
        check("named keys in any case", find(b, 99).binding.equals("KEY_ENTER")
            && find(b, 100).binding.equals("KEY_ESC"));
    }

    private static void aTypoFailsLoudly() {
        boolean threw = false;
        try {
            PadKeys.bindings(map("aa", "X"));
        } catch (IllegalArgumentException e) {
            threw = e.getMessage().contains("aa");
        }
        check("an unknown button is an error naming it", threw);
        threw = false;
        try {
            PadKeys.bindings(map("a", "Xx"));
        } catch (IllegalArgumentException e) {
            threw = e.getMessage().contains("Xx");
        }
        check("an unknown key is an error naming it", threw);
        threw = false;
        try {
            PadKeys.bindings(map("dpad", "X"));
        } catch (IllegalArgumentException e) {
            threw = true;
        }
        check("a four-way takes only arrows or wasd", threw);
    }

    private static void theProfileIsGameNativesFormat() throws Exception {
        String json = PadKeys.profileJson(7, "strom: ff8", map("a", "X", "dpad", "arrows"));
        Object o = Json.parse(json);
        check("id and name", "7".equals(Json.scalar(o, "id")) && "strom: ff8".equals(Json.str(o, "name")));
        check("a wildcard controller", "*".equals(Json.str(Json.list(Json.path(o, "controllers")).get(0), "id")));
        List<?> binds = Json.list(Json.path(Json.list(Json.path(o, "controllers")).get(0), "controllerBindings"));
        check("one binding per button plus four for the dpad", binds.size() == 5);
        check("bindings carry keyCode and binding",
            "96".equals(Json.scalar(binds.get(0), "keyCode")) && "KEY_X".equals(Json.str(binds.get(0), "binding")));
        check("no on-screen elements: the importer fills those in",
            Json.list(Json.path(o, "elements")).isEmpty());
    }

    private static void emptyMeansXInput() {
        check("no mapping means no profile", !PadKeys.any(null) && !PadKeys.any(map()));
        check("any mapping means a profile", PadKeys.any(map("a", "X")));
    }

    private static void check(String what, boolean ok) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) {
            failures++;
        }
    }
}
