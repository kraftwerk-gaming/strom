package gaming.kraftwerk.strom.catalog;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Turns a player's picks into the mod layers to unpack, and says why a pick
 * cannot be offered when it cannot.
 *
 * <p>Pure logic on purpose: no Android type appears here, so the rules that
 * decide what gets downloaded onto a phone, and what silently would not
 * have happened, are tested on the plain JDK by {@code OptionsTest}.
 *
 * <p>Picks are text keyed by option, and only the ones differing from the
 * manifest default are stored -- the same rule the desktop launcher applies
 * to {@code settings.json}, so a default that changes upstream changes for
 * a player who never touched it.
 */
public final class Options {
    private Options() {
    }

    /** The value in force for one option: the player's pick, else the default. */
    public static String value(Setting s, Map<String, String> picks) {
        String v = (picks == null) ? null : picks.get(s.key);
        // A pick the manifest no longer offers is a stale preference from an
        // older publication rather than a value: fall back, instead of
        // hunting for a layer that cannot exist.
        return (v != null && s.values().contains(v)) ? v : s.defaultValue;
    }

    /** Every option's value in force, keyed by option. */
    public static Map<String, String> effective(List<Setting> settings, Map<String, String> picks) {
        Map<String, String> out = new LinkedHashMap<String, String>();
        for (Setting s : settings) {
            out.put(s.key, value(s, picks));
        }
        return out;
    }

    /** The layers a set of picks selects, in manifest = extraction order. */
    public static List<Layer> select(Game g, Map<String, String> picks) {
        Map<String, String> eff = effective(g.settings, picks);
        List<Layer> out = new ArrayList<Layer>();
        for (Layer l : g.layers) {
            if (matches(l, eff)) {
                out.add(l);
            }
        }
        return out;
    }

    /**
     * What Play has to do for the game's files to match the picks.
     *
     * <p>{@code applied} is the set of layer names already unpacked into the
     * game directory, which is why this is a plan and not just a list: a
     * layer already there is not fetched again, and one that is there but no
     * longer picked cannot be removed by unpacking anything.
     */
    public static Plan plan(Game g, Map<String, String> picks, Set<String> applied) {
        return new Plan(select(g, picks),
            (applied == null) ? Collections.<String>emptySet() : applied);
    }

    /** Whether a layer is pulled in by the values in force. */
    private static boolean matches(Layer l, Map<String, String> eff) {
        if (l.key == null || l.value == null || !l.value.equals(eff.get(l.key))) {
            return false;
        }
        if (l.requiresKey == null) {
            return true;
        }
        // A parent the manifest does not publish cannot be satisfied, so the
        // layer stays out rather than being treated as unconditional.
        return l.requiresValue != null && l.requiresValue.equals(eff.get(l.requiresKey));
    }

    // ---- what the UI may offer -------------------------------------------

    /**
     * Why this option cannot be honoured on this device, or null when it can.
     *
     * <p>Every branch here is a row the player must not be able to set,
     * because setting it would do nothing at all.
     */
    public static String unavailable(Game g, Setting s, Map<String, String> picks) {
        if (s.values().size() < 2) {
            return "not settable here";
        }
        List<Layer> mine = forKey(g.layers, s.key);
        if (mine.isEmpty() && !gates(g.layers, s.key)) {
            // The option changes files inside the base payload rather than
            // adding any, and the base is pinned as it was built.
            return "desktop only: this option is baked into the download";
        }
        if (!mine.isEmpty()) {
            String parent = blockedBy(mine, effective(g.settings, picks));
            if (parent != null) {
                return "needs " + parent;
            }
        }
        if (selectable(g, s, picks).size() < 2) {
            return "not published yet: " + join(unpublished(g, s, picks));
        }
        return null;
    }

    /** The values a player may actually pick, in cycle order. */
    public static List<String> selectable(Game g, Setting s, Map<String, String> picks) {
        List<String> out = new ArrayList<String>();
        for (String v : s.values()) {
            if (unpinned(wouldSelect(g, s, v, picks)).isEmpty()) {
                out.add(v);
            }
        }
        return out;
    }

    /** The values whose layers the manifest describes but has not pinned. */
    public static List<String> unpublished(Game g, Setting s, Map<String, String> picks) {
        List<String> out = new ArrayList<String>();
        for (String v : s.values()) {
            if (!unpinned(wouldSelect(g, s, v, picks)).isEmpty()) {
                out.add(v);
            }
        }
        return out;
    }

    /**
     * The layers one value of an option would pull in, given the other picks.
     *
     * <p>Both the layers keyed on the option and the ones it merely gates: a
     * parent switch like FF8's {@code ragnarok} publishes no layer of its own
     * and is still the thing that decides whether its difficulty variant is
     * downloaded, so it is neither desktop-only nor free of consequences.
     */
    public static List<Layer> wouldSelect(Game g, Setting s, String value,
        Map<String, String> picks) {
        Map<String, String> hypothetical = new LinkedHashMap<String, String>(picks);
        hypothetical.put(s.key, value);
        Map<String, String> eff = effective(g.settings, hypothetical);
        List<Layer> out = new ArrayList<Layer>();
        for (Layer l : g.layers) {
            if ((s.key.equals(l.key) || s.key.equals(l.requiresKey)) && matches(l, eff)) {
                out.add(l);
            }
        }
        return out;
    }

    public static long bytes(List<Layer> layers) {
        long n = 0;
        for (Layer l : layers) {
            n += l.size;
        }
        return n;
    }

    /**
     * The unmet parent switch shared by every layer of an option, or null.
     *
     * <p>An option whose layers all sit behind a parent that is off is not
     * unavailable in principle, only right now, and saying which switch
     * turns it on is the difference between a grayed row and a dead one.
     */
    private static String blockedBy(List<Layer> mine, Map<String, String> eff) {
        String unmet = null;
        for (Layer l : mine) {
            if (l.requiresKey == null) {
                return null;
            }
            if (l.requiresValue != null && l.requiresValue.equals(eff.get(l.requiresKey))) {
                return null;
            }
            if (unmet == null) {
                unmet = l.requiresKey + " = " + l.requiresValue;
            }
        }
        return unmet;
    }

    private static List<Layer> forKey(List<Layer> layers, String key) {
        List<Layer> out = new ArrayList<Layer>();
        for (Layer l : layers) {
            if (key.equals(l.key)) {
                out.add(l);
            }
        }
        return out;
    }

    /** Whether any layer at all is gated on this option. */
    private static boolean gates(List<Layer> layers, String key) {
        for (Layer l : layers) {
            if (key.equals(l.requiresKey)) {
                return true;
            }
        }
        return false;
    }

    private static List<Layer> unpinned(List<Layer> layers) {
        List<Layer> out = new ArrayList<Layer>();
        for (Layer l : layers) {
            if (!l.pinned()) {
                out.add(l);
            }
        }
        return out;
    }

    // ---- storage ---------------------------------------------------------

    /** Picks as stored: one {@code key=value} line per non-default pick. */
    public static String encode(List<Setting> settings, Map<String, String> picks) {
        StringBuilder b = new StringBuilder();
        for (Setting s : settings) {
            String v = value(s, picks);
            if (v == null || v.equals(s.defaultValue)) {
                continue;
            }
            b.append(s.key).append('=').append(v).append('\n');
        }
        return b.toString();
    }

    public static Map<String, String> decode(String stored) {
        Map<String, String> out = new LinkedHashMap<String, String>();
        if (stored == null) {
            return out;
        }
        for (String line : stored.split("\n")) {
            int eq = line.indexOf('=');
            if (eq > 0) {
                out.put(line.substring(0, eq), line.substring(eq + 1));
            }
        }
        return out;
    }

    // ---- plan ------------------------------------------------------------

    /** The layers a set of picks resolves to, against what is already there. */
    public static final class Plan {
        /** Every selected layer, in extraction order. */
        public final List<Layer> selected;
        /** Selected minus already applied: what to fetch, in extraction order. */
        public final List<Layer> fetch;
        /** Selected layers with no CID, so the pick cannot be honoured at all. */
        public final List<Layer> unpinned;
        /** Applied layers the picks no longer select; unpacking cannot undo them. */
        public final List<String> stale;
        /** Bytes {@code fetch} will pull, as far as the manifest says. */
        public final long bytes;
        /** Why this must not launch as picked, or null when it may. */
        public final String problem;

        private Plan(List<Layer> selected, Set<String> applied) {
            List<Layer> toFetch = new ArrayList<Layer>();
            List<Layer> missing = new ArrayList<Layer>();
            List<String> names = new ArrayList<String>();
            long total = 0;
            for (Layer l : selected) {
                names.add(l.name);
                if (!l.pinned()) {
                    missing.add(l);
                } else if (!applied.contains(l.name)) {
                    toFetch.add(l);
                    total += l.size;
                }
            }
            List<String> gone = new ArrayList<String>();
            for (String a : applied) {
                if (!names.contains(a)) {
                    gone.add(a);
                }
            }
            this.selected = Collections.unmodifiableList(selected);
            this.fetch = Collections.unmodifiableList(toFetch);
            this.unpinned = Collections.unmodifiableList(missing);
            this.stale = Collections.unmodifiableList(gone);
            this.bytes = total;
            this.problem = problem(missing, gone);
        }

        private static String problem(List<Layer> unpinned, List<String> stale) {
            if (!unpinned.isEmpty()) {
                return "not published yet: " + join(names(unpinned))
                    + ". Turn that option back off, or wait for it to be pinned.";
            }
            if (!stale.isEmpty()) {
                // Overlay lowers carry no whiteouts and neither does a copy,
                // so there is no download that takes a mod back out again.
                return "already unpacked: " + join(stale)
                    + ". Unpacking cannot take a mod back out, so playing without it"
                    + " means downloading this game again from scratch.";
            }
            return null;
        }
    }

    private static List<String> names(List<Layer> layers) {
        List<String> out = new ArrayList<String>();
        for (Layer l : layers) {
            out.add(l.name);
        }
        return out;
    }

    private static String join(List<String> parts) {
        StringBuilder b = new StringBuilder();
        for (String p : parts) {
            if (b.length() > 0) {
                b.append(", ");
            }
            b.append(p);
        }
        return b.toString();
    }
}
