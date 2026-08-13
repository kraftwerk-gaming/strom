package gaming.kraftwerk.strom.catalog;

import java.util.ArrayList;
import java.util.List;

/**
 * One optional mod layer from the manifest's {@code layers} array.
 *
 * <p>A layer is a partial tree unpacked over the base payload, which is
 * exactly what the desktop does with it: the recipe stacks each mod as its
 * own overlay lower, and a lower can only add a file or win a path
 * conflict, never delete one. So array order is extraction order, lowest
 * priority first, and later files win. See docs/android.md, "Why
 * unzip-in-order is exactly equivalent to the overlay merge".
 */
public final class Layer {
    public String name;
    public String key;
    public String value;
    /** null until this layer's tree is pinned; it cannot be fetched before. */
    public String cid;
    /** Bytes, 0 when the manifest published no size. */
    public long size;

    /**
     * A parent switch this layer additionally depends on, or null.
     *
     * <p>FF8's Ragnarok mod has a difficulty enum that means nothing unless
     * the mod itself is on, and key/value alone cannot say that: a player
     * who never enabled Ragnarok still carries the enum's default, and
     * would be handed a rebalance mod they never asked for.
     */
    public String requiresKey;
    public String requiresValue;

    public boolean pinned() {
        return cid != null && !cid.isEmpty();
    }

    /** Parse a manifest {@code layers} array; absent reads as none. */
    public static List<Layer> parseAll(Object node) {
        List<Layer> out = new ArrayList<Layer>();
        for (Object o : Json.list(node)) {
            String name = Json.str(o, "name");
            if (name == null || name.isEmpty()) {
                continue;   // nothing could record it as applied
            }
            Layer l = new Layer();
            l.name = name;
            l.key = Json.str(o, "key");
            l.value = Json.scalar(o, "value");
            l.cid = Json.str(o, "cid");
            l.size = Json.num(o, 0L, "size");
            l.requiresKey = Json.str(o, "requires", "key");
            l.requiresValue = Json.scalar(o, "requires", "value");
            out.add(l);
        }
        return out;
    }

    @Override
    public String toString() {
        return "Layer{" + name + " " + key + "=" + value
            + (pinned() ? "" : " unpinned") + "}";
    }
}
