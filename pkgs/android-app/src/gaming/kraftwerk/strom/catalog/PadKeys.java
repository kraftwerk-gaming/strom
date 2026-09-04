package gaming.kraftwerk.strom.catalog;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A game's `android.padKeys` -- physical pad buttons mapped to the keys
 * the game reads -- rendered as a GameNative Input Controls profile.
 *
 * <p>Every GameNative-specific fact lives here and nowhere else: the
 * Android key codes its profiles bind by, the negative pseudo-codes it
 * uses for stick directions, the {@code KEY_*} binding vocabulary, and
 * the one trap in its axis handling. The manifest speaks in buttons and
 * key names; the recipe never sees any of this.
 */
public final class PadKeys {
    private PadKeys() {
    }

    /** Android KeyEvent codes, what GameNative's controller bindings key on. */
    private static final Map<String, Integer> BUTTONS = new LinkedHashMap<String, Integer>();
    static {
        BUTTONS.put("a", 96);
        BUTTONS.put("b", 97);
        BUTTONS.put("x", 99);
        BUTTONS.put("y", 100);
        BUTTONS.put("l1", 102);
        BUTTONS.put("r1", 103);
        BUTTONS.put("l2", 104);
        BUTTONS.put("r2", 105);
        BUTTONS.put("l3", 106);
        BUTTONS.put("r3", 107);
        BUTTONS.put("start", 108);
        BUTTONS.put("select", 109);
    }

    /**
     * Stick directions as GameNative's ExternalControllerBinding pseudo
     * key codes, in the order left, right, up, down.
     *
     * <p>The vertical pair looks inverted and is not: {@code
     * getKeyCodeForAxis(AXIS_Y, +)} returns {@code AXIS_Y_NEGATIVE} (-3)
     * while Android's positive Y is stick DOWN, so -3 must carry the down
     * key. Gamepad bindings never notice because they forward the raw
     * value; key bindings do. Measured on an AYN Thor: with -3 as up the
     * stick moved the cursor the wrong way.
     */
    private static final int[] LEFT_STICK = { -1, -2, -4, -3 };
    private static final int[] RIGHT_STICK = { -5, -6, -8, -7 };
    /** The hat arrives as KEYCODE_DPAD_* through getKeyCodeForAxis. */
    private static final int[] DPAD = { 21, 22, 19, 20 };

    private static final Map<String, String> NAMED = new LinkedHashMap<String, String>();
    static {
        NAMED.put("UP", "KEY_UP");
        NAMED.put("DOWN", "KEY_DOWN");
        NAMED.put("LEFT", "KEY_LEFT");
        NAMED.put("RIGHT", "KEY_RIGHT");
        NAMED.put("ENTER", "KEY_ENTER");
        NAMED.put("ESC", "KEY_ESC");
        NAMED.put("SPACE", "KEY_SPACE");
        NAMED.put("TAB", "KEY_TAB");
        NAMED.put("BKSP", "KEY_BKSP");
        NAMED.put("DEL", "KEY_DEL");
        NAMED.put("SHIFT", "KEY_SHIFT_L");
        NAMED.put("CTRL", "KEY_CTRL_L");
        NAMED.put("ALT", "KEY_ALT_L");
    }

    /** One controller binding: an Android key code to a GameNative binding name. */
    public static final class Bind {
        public final int keyCode;
        public final String binding;

        Bind(int keyCode, String binding) {
            this.keyCode = keyCode;
            this.binding = binding;
        }
    }

    /** True when the manifest maps anything, i.e. the game wants keys, not XInput. */
    public static boolean any(Map<String, String> padKeys) {
        return padKeys != null && !padKeys.isEmpty();
    }

    /**
     * The bindings for a manifest mapping, in a stable order. Throws on a
     * button or key the vocabulary does not have, because a typo in a
     * recipe must fail loudly rather than leave a button dead.
     */
    public static List<Bind> bindings(Map<String, String> padKeys) {
        List<Bind> out = new ArrayList<Bind>();
        for (Map.Entry<String, String> e : padKeys.entrySet()) {
            String button = e.getKey();
            String value = e.getValue();
            if (BUTTONS.containsKey(button)) {
                out.add(new Bind(BUTTONS.get(button), key(value)));
            } else if ("dpad".equals(button)) {
                fourWay(out, DPAD, value);
            } else if ("leftStick".equals(button)) {
                fourWay(out, LEFT_STICK, value);
            } else if ("rightStick".equals(button)) {
                fourWay(out, RIGHT_STICK, value);
            } else {
                throw new IllegalArgumentException("padKeys: no such button: " + button);
            }
        }
        return out;
    }

    private static void fourWay(List<Bind> out, int[] codes, String value) {
        String[] keys;
        if ("arrows".equals(value)) {
            keys = new String[] { "KEY_LEFT", "KEY_RIGHT", "KEY_UP", "KEY_DOWN" };
        } else if ("wasd".equals(value)) {
            keys = new String[] { "KEY_A", "KEY_D", "KEY_W", "KEY_S" };
        } else {
            throw new IllegalArgumentException("padKeys: a four-way takes arrows or wasd, not " + value);
        }
        for (int i = 0; i < 4; i++) {
            out.add(new Bind(codes[i], keys[i]));
        }
    }

    private static String key(String name) {
        if (name.length() == 1) {
            char c = Character.toUpperCase(name.charAt(0));
            if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
                return "KEY_" + c;
            }
        }
        String named = NAMED.get(name.toUpperCase());
        if (named == null) {
            throw new IllegalArgumentException("padKeys: no such key: " + name);
        }
        return named;
    }

    /**
     * The profile as GameNative's `.icp` JSON. Wildcard controller, so it
     * applies to whatever pad is plugged in; no on-screen elements, which
     * the importer fills from its default profile so touch keeps working.
     */
    public static String profileJson(int id, String name, Map<String, String> padKeys) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"id\":").append(id)
            .append(",\"name\":").append(quote(name))
            .append(",\"cursorSpeed\":1,\"elements\":[],\"controllers\":[{\"id\":\"*\","
                + "\"name\":\"Wildcard Controller\",\"controllerBindings\":[");
        boolean first = true;
        for (Bind b : bindings(padKeys)) {
            if (!first) {
                sb.append(',');
            }
            first = false;
            sb.append("{\"keyCode\":").append(b.keyCode)
                .append(",\"binding\":\"").append(b.binding).append("\"}");
        }
        sb.append("]}]}");
        return sb.toString();
    }

    /**
     * The mapping as a player reads it, for the setup message on a runtime
     * that cannot take the profile: "A to X, B to C, dpad to arrows".
     */
    public static String describe(Map<String, String> padKeys) {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : padKeys.entrySet()) {
            if (sb.length() > 0) {
                sb.append(", ");
            }
            sb.append(e.getKey()).append(" to ").append(e.getValue());
        }
        return sb.toString();
    }

    private static String quote(String s) {
        StringBuilder sb = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"' || c == '\\') {
                sb.append('\\');
            }
            sb.append(c);
        }
        return sb.append('"').toString();
    }
}
