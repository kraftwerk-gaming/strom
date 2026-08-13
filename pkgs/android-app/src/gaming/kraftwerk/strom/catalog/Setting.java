package gaming.kraftwerk.strom.catalog;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * One player-facing option from the manifest's {@code settings} array.
 *
 * <p>A projection of the game recipe's {@code settingsSchema}, which is
 * the same list the desktop couch launcher renders, so a phone and a couch
 * can never offer different options for the same game.
 *
 * <p>Values are carried as text whatever the manifest types them as: a
 * bool's default arrives as JSON {@code false} while a layer's value for
 * the same option is the string {@code "true"}, and a pick has to compare
 * equal to both.
 */
public final class Setting {
    public static final String BOOL = "bool";
    public static final String ENUM = "enum";

    public String key;
    public String kind;
    public String label;
    public String help;
    public String defaultValue;
    /** Only an enum publishes these; a bool's two values are implied. */
    public List<String> choices = Collections.emptyList();

    /** Every value this option can take, in the order the UI cycles them. */
    public List<String> values() {
        if (BOOL.equals(kind)) {
            return Arrays.asList("false", "true");
        }
        if (ENUM.equals(kind)) {
            return choices;
        }
        // An int or a list of packages: published for the desktop, and not
        // something this client knows how to put in front of a thumb.
        return Collections.emptyList();
    }

    /** What the user sees; falls back to the key so a row is never blank. */
    public String title() {
        return (label != null && !label.isEmpty()) ? label : key;
    }

    /** Parse a manifest {@code settings} array; absent reads as none. */
    public static List<Setting> parseAll(Object node) {
        List<Setting> out = new ArrayList<Setting>();
        for (Object o : Json.list(node)) {
            String key = Json.str(o, "key");
            if (key == null || key.isEmpty()) {
                continue;   // a pick could not be stored under it
            }
            Setting s = new Setting();
            s.key = key;
            s.kind = Json.str(o, "kind");
            s.label = Json.str(o, "label");
            s.help = Json.str(o, "help");
            s.defaultValue = Json.scalar(o, "default");
            List<String> choices = new ArrayList<String>();
            for (Object c : Json.list(o, "choices")) {
                if (c instanceof String) {
                    choices.add((String) c);
                }
            }
            s.choices = choices;
            if (s.defaultValue == null) {
                // The schema always carries one; a row without it still has
                // to have a value in force, or nothing can be compared.
                s.defaultValue = BOOL.equals(s.kind) ? "false"
                    : (choices.isEmpty() ? "" : choices.get(0));
            }
            out.add(s);
        }
        return out;
    }

    @Override
    public String toString() {
        return "Setting{" + key + " " + kind + " default=" + defaultValue + "}";
    }
}
