package gaming.kraftwerk.strom.catalog;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Tests the rules that decide which mod layers a phone downloads.
 *
 * <p>A mistake here is not a wrong pixel: it is a multi-gigabyte download
 * the player did not ask for, or worse, a game launched with a tree that
 * does not match the options they picked -- a mod they are looking for and
 * cannot find, or one they turned off and still get. Unpacking a layer
 * cannot be undone either (overlay lowers carry no whiteouts, and neither
 * does a copy), so "refused with a reason" and "quietly ignored" are the
 * two outcomes that have to be told apart.
 *
 * <p>Plain main(), no JUnit, no Android types: the resolution lives in
 * {@link Options} precisely so it runs under the same javac the APK is
 * built with, on the plain JDK.
 */
public final class OptionsTest {
    private static int failures = 0;

    /**
     * FF8's published shape, cut down to the interesting layers: an enum
     * with one layer per non-default choice, two bools (one of which
     * expands to several packs), a parent switch with a difficulty enum
     * behind it whose standard variant is not pinned yet, and an option
     * that publishes no layer at all because it only changes files inside
     * the base download.
     */
    private static final String MANIFEST = "{ \"android\": {"
        + "  \"settings\": ["
        + "    { \"key\": \"music\", \"kind\": \"enum\", \"label\": \"Music\","
        + "      \"help\": \"Soundtrack replacement.\", \"default\": \"vanilla\","
        + "      \"choices\": [\"vanilla\", \"psx\", \"orchestral\"] },"
        + "    { \"key\": \"voices\", \"kind\": \"bool\", \"label\": \"Voices\","
        + "      \"help\": \"Fan voice acting.\", \"default\": false },"
        + "    { \"key\": \"textures\", \"kind\": \"bool\", \"label\": \"Textures\","
        + "      \"help\": \"Upscaled textures.\", \"default\": false },"
        + "    { \"key\": \"ragnarok\", \"kind\": \"bool\", \"label\": \"Ragnarok\","
        + "      \"help\": \"Rebalance mod.\", \"default\": false },"
        + "    { \"key\": \"ragnarokMode\", \"kind\": \"enum\", \"label\": \"Ragnarok mode\","
        + "      \"help\": \"Difficulty variant.\", \"default\": \"standard\","
        + "      \"choices\": [\"standard\", \"lionheart\"] },"
        + "    { \"key\": \"ffnx\", \"kind\": \"bool\", \"label\": \"FFNx\","
        + "      \"help\": \"Modern renderer.\", \"default\": true }"
        + "  ],"
        + "  \"layers\": ["
        + "    { \"name\": \"ff8-voices\", \"key\": \"voices\", \"value\": \"true\","
        + "      \"cid\": \"QmVoices\", \"size\": 25000000 },"
        + "    { \"name\": \"ff8-music-psx\", \"key\": \"music\", \"value\": \"psx\","
        + "      \"cid\": \"QmPsx\", \"size\": 120000000 },"
        + "    { \"name\": \"ff8-music-orchestral\", \"key\": \"music\","
        + "      \"value\": \"orchestral\", \"cid\": \"QmOrch\", \"size\": 779000000 },"
        + "    { \"name\": \"ff8-texturepack-chars\", \"key\": \"textures\","
        + "      \"value\": \"true\", \"cid\": \"QmT1\", \"size\": 1000 },"
        + "    { \"name\": \"ff8-texturepack-spells\", \"key\": \"textures\","
        + "      \"value\": \"true\", \"cid\": \"QmT2\", \"size\": 2000 },"
        + "    { \"name\": \"ff8-texturepack-worldmap\", \"key\": \"textures\","
        + "      \"value\": \"true\", \"cid\": \"QmT3\", \"size\": 4000 },"
        + "    { \"name\": \"ff8-texturepack-menus\", \"key\": \"textures\","
        + "      \"value\": \"true\", \"cid\": \"QmT4\", \"size\": 8000 },"
        + "    { \"name\": \"ff8-texturepack-monsters\", \"key\": \"textures\","
        + "      \"value\": \"true\", \"cid\": \"QmT5\", \"size\": 16000 },"
        + "    { \"name\": \"ff8-ragnarok-standard\", \"key\": \"ragnarokMode\","
        + "      \"value\": \"standard\", \"cid\": null, \"size\": 340000000,"
        + "      \"requires\": { \"key\": \"ragnarok\", \"value\": \"true\" } },"
        + "    { \"name\": \"ff8-ragnarok-lionheart\", \"key\": \"ragnarokMode\","
        + "      \"value\": \"lionheart\", \"cid\": \"QmLion\", \"size\": 341000000,"
        + "      \"requires\": { \"key\": \"ragnarok\", \"value\": \"true\" } }"
        + "  ] } }";

    public static void main(String[] args) throws Exception {
        theManifestParses();
        defaultsSelectNothing();
        aBoolSelectsItsLayer();
        anEnumSelectsOnlyTheChosenLayer();
        oneKeyWithSeveralLayersSelectsAllOfThem();
        layersComeInManifestOrderNotPickOrder();
        anUnpinnedLayerIsRefusedNotSkipped();
        aGatedLayerStaysOutUntilItsParentIsOn();
        aDeselectionIsRefusedNotIgnored();
        anAppliedLayerIsNotFetchedTwice();
        anOptionWithNoLayersIsDesktopOnly();
        aParentSwitchIsNotMistakenForDesktopOnly();
        aGatedOptionNamesTheSwitchThatEnablesIt();
        aStalePickFallsBackToTheDefault();
        onlyNonDefaultPicksAreStored();

        if (failures > 0) {
            System.err.println(failures + " test(s) failed");
            System.exit(1);
        }
        System.out.println("all option selection tests passed");
    }

    // ---- tests -----------------------------------------------------------

    private static void theManifestParses() throws Exception {
        Game g = game();
        check("every published option is read", g.settings.size() == 6);
        check("every layer is read", g.layers.size() == 10);
        check("a bool default arrives as text",
            "false".equals(setting(g, "voices").defaultValue));
        check("an enum keeps its choices",
            setting(g, "music").choices.equals(list("vanilla", "psx", "orchestral")));
        check("an unpinned layer has no CID", !layer(g, "ff8-ragnarok-standard").pinned());
        check("a layer's size is read", layer(g, "ff8-music-orchestral").size == 779000000L);
        check("a gate is read",
            "ragnarok".equals(layer(g, "ff8-ragnarok-lionheart").requiresKey)
                && "true".equals(layer(g, "ff8-ragnarok-lionheart").requiresValue));
    }

    private static void defaultsSelectNothing() throws Exception {
        Options.Plan p = Options.plan(game(), picks(), applied());
        check("a player who picked nothing downloads only the base",
            names(p.selected).isEmpty() && names(p.fetch).isEmpty());
        check("nothing to download means nothing to say", p.problem == null);
        check("and no extra bytes", p.bytes == 0);
    }

    private static void aBoolSelectsItsLayer() throws Exception {
        Options.Plan p = Options.plan(game(), picks("voices", "true"), applied());
        check("a bool selects the layer published for \"true\"",
            names(p.fetch).equals(list("ff8-voices")));
        check("and only that one", p.selected.size() == 1);
        check("its size is what will be downloaded", p.bytes == 25000000L);
    }

    private static void anEnumSelectsOnlyTheChosenLayer() throws Exception {
        Options.Plan p = Options.plan(game(), picks("music", "orchestral"), applied());
        check("an enum selects the layer for the chosen value",
            names(p.fetch).equals(list("ff8-music-orchestral")));
        check("the other choice's layer stays out",
            !names(p.selected).contains("ff8-music-psx"));
    }

    private static void oneKeyWithSeveralLayersSelectsAllOfThem() throws Exception {
        Options.Plan p = Options.plan(game(), picks("textures", "true"), applied());
        check("every layer sharing the key and value is selected",
            names(p.fetch).equals(list(
                "ff8-texturepack-chars", "ff8-texturepack-spells",
                "ff8-texturepack-worldmap", "ff8-texturepack-menus",
                "ff8-texturepack-monsters")));
        check("their sizes add up", p.bytes == 31000L);
    }

    /**
     * Extraction order is the manifest's array order, because that is the
     * overlay's priority order reversed: a later layer's files win, so a
     * plan that fetches them in pick order or in map order would produce a
     * different tree from the desktop's merged view.
     */
    private static void layersComeInManifestOrderNotPickOrder() throws Exception {
        Map<String, String> picks = new LinkedHashMap<String, String>();
        picks.put("textures", "true");
        picks.put("music", "psx");
        picks.put("voices", "true");

        Options.Plan p = Options.plan(game(), picks, applied());
        check("selection follows the manifest, not the order they were picked",
            names(p.fetch).equals(list(
                "ff8-voices", "ff8-music-psx",
                "ff8-texturepack-chars", "ff8-texturepack-spells",
                "ff8-texturepack-worldmap", "ff8-texturepack-menus",
                "ff8-texturepack-monsters")));
    }

    private static void anUnpinnedLayerIsRefusedNotSkipped() throws Exception {
        Options.Plan p = Options.plan(game(), picks("ragnarok", "true"), applied());
        check("a selected layer with no CID is reported",
            names(p.unpinned).equals(list("ff8-ragnarok-standard")));
        check("it is not fetched", names(p.fetch).isEmpty());
        // Launching anyway would start a game without the mod the player
        // just turned on, and they would have no way to tell why.
        check("and the launch is refused with the layer named",
            p.problem != null && p.problem.contains("ff8-ragnarok-standard"));
    }

    private static void aGatedLayerStaysOutUntilItsParentIsOn() throws Exception {
        Game g = game();
        Options.Plan off = Options.plan(g, picks("ragnarokMode", "lionheart"), applied());
        check("a difficulty variant is not downloaded while the mod is off",
            names(off.selected).isEmpty() && off.problem == null);

        Map<String, String> both = new LinkedHashMap<String, String>();
        both.put("ragnarok", "true");
        both.put("ragnarokMode", "lionheart");
        Options.Plan on = Options.plan(g, both, applied());
        check("with the mod on, the chosen variant is downloaded",
            names(on.fetch).equals(list("ff8-ragnarok-lionheart")));
        check("and the variant that was not chosen stays out, unpinned or not",
            on.problem == null && on.unpinned.isEmpty());
    }

    private static void aDeselectionIsRefusedNotIgnored() throws Exception {
        Options.Plan p = Options.plan(game(), picks(), applied("ff8-voices"));
        check("a layer already unpacked but no longer picked is reported stale",
            p.stale.equals(list("ff8-voices")));
        check("the picks alone select nothing", names(p.selected).isEmpty());
        // The whole point: no download can take a merged tree back out, so
        // the only honest answers are "start over" or "do not launch".
        check("so the launch is refused rather than run with the old tree",
            p.problem != null && p.problem.contains("ff8-voices"));
        check("and the reason says a fresh download is what it takes",
            p.problem.contains("downloading this game again"));
    }

    private static void anAppliedLayerIsNotFetchedTwice() throws Exception {
        Map<String, String> picks = new LinkedHashMap<String, String>();
        picks.put("voices", "true");
        picks.put("music", "orchestral");

        Options.Plan p = Options.plan(game(), picks, applied("ff8-voices"));
        check("both layers are still what the picks mean",
            names(p.selected).equals(list("ff8-voices", "ff8-music-orchestral")));
        check("only the missing one is fetched",
            names(p.fetch).equals(list("ff8-music-orchestral")));
        check("and only its bytes are counted", p.bytes == 779000000L);
        check("nothing is stale, so nothing is refused",
            p.stale.isEmpty() && p.problem == null);
    }

    private static void anOptionWithNoLayersIsDesktopOnly() throws Exception {
        Game g = game();
        String why = Options.unavailable(g, setting(g, "ffnx"), picks());
        check("an option that publishes no layer cannot be set here",
            why != null && why.contains("desktop only"));
        check("while one that does is offered",
            Options.unavailable(g, setting(g, "voices"), picks()) == null);
    }

    private static void aParentSwitchIsNotMistakenForDesktopOnly() throws Exception {
        Game g = game();
        String why = Options.unavailable(g, setting(g, "ragnarok"), picks());
        check("a switch that gates a layer is not called desktop only",
            why != null && !why.contains("desktop only"));
        check("it is grayed out because a variant is unpinned",
            why.contains("not published yet"));

        // Pin the missing variant: the same switch has to become settable,
        // which is what proves the grayed row was about pinning and not
        // about the switch publishing no layer of its own.
        layer(g, "ff8-ragnarok-standard").cid = "QmStandard";
        check("pinning the variant makes the switch settable",
            Options.unavailable(g, setting(g, "ragnarok"), picks()) == null);
        check("and turning it on then selects the default variant",
            names(Options.plan(g, picks("ragnarok", "true"), applied()).fetch)
                .equals(list("ff8-ragnarok-standard")));
    }

    private static void aGatedOptionNamesTheSwitchThatEnablesIt() throws Exception {
        Game g = game();
        String why = Options.unavailable(g, setting(g, "ragnarokMode"), picks());
        check("an option behind an off switch says which switch",
            "needs ragnarok = true".equals(why));
        // With the switch on the row is still not settable, but for the
        // other reason and it has to say so: one of the two variants has no
        // CID yet, so cycling onto it would select a layer nothing can fetch.
        check("with the switch on, the reason becomes the unpinned variant",
            "not published yet: standard".equals(
                Options.unavailable(g, setting(g, "ragnarokMode"), picks("ragnarok", "true"))));
        layer(g, "ff8-ragnarok-standard").cid = "QmStandard";
        check("and it is settable once both variants are pinned",
            Options.unavailable(g, setting(g, "ragnarokMode"),
                picks("ragnarok", "true")) == null);
    }

    private static void aStalePickFallsBackToTheDefault() throws Exception {
        Game g = game();
        // A preference stored before the recipe dropped a choice.
        check("a value the manifest no longer offers is not honoured",
            "vanilla".equals(Options.value(setting(g, "music"), picks("music", "vinyl"))));
        check("and selects nothing",
            Options.plan(g, picks("music", "vinyl"), applied()).selected.isEmpty());
    }

    private static void onlyNonDefaultPicksAreStored() throws Exception {
        Game g = game();
        Map<String, String> picks = new LinkedHashMap<String, String>();
        picks.put("music", "vanilla");
        picks.put("voices", "true");

        String stored = Options.encode(g.settings, picks);
        // The same rule the desktop launcher applies to settings.json, so a
        // default that changes upstream changes for whoever never touched it.
        check("a pick equal to the default is not written",
            "voices=true\n".equals(stored));
        check("what is written reads back", Options.decode(stored).size() == 1
            && "true".equals(Options.decode(stored).get("voices")));
        check("and resolves to the same layers",
            names(Options.plan(g, Options.decode(stored), applied()).fetch)
                .equals(list("ff8-voices")));
    }

    // ---- helpers ---------------------------------------------------------

    private static Game game() throws Exception {
        Object m = Json.parse(MANIFEST);
        Game g = new Game();
        g.slug = "final-fantasy-viii";
        g.settings = Setting.parseAll(Json.path(m, "android", "settings"));
        g.layers = Layer.parseAll(Json.path(m, "android", "layers"));
        return g;
    }

    private static Setting setting(Game g, String key) {
        for (Setting s : g.settings) {
            if (key.equals(s.key)) {
                return s;
            }
        }
        throw new IllegalArgumentException("no setting " + key);
    }

    private static Layer layer(Game g, String name) {
        for (Layer l : g.layers) {
            if (name.equals(l.name)) {
                return l;
            }
        }
        throw new IllegalArgumentException("no layer " + name);
    }

    private static Map<String, String> picks(String... kv) {
        Map<String, String> m = new LinkedHashMap<String, String>();
        for (int i = 0; i + 1 < kv.length; i += 2) {
            m.put(kv[i], kv[i + 1]);
        }
        return m;
    }

    private static Set<String> applied(String... names) {
        Set<String> s = new LinkedHashSet<String>();
        for (int i = 0; i < names.length; i++) {
            s.add(names[i]);
        }
        return s;
    }

    private static List<String> names(List<Layer> layers) {
        List<String> out = new ArrayList<String>();
        for (Layer l : layers) {
            out.add(l.name);
        }
        return out;
    }

    private static List<String> list(String... items) {
        List<String> out = new ArrayList<String>();
        for (int i = 0; i < items.length; i++) {
            out.add(items[i]);
        }
        return out;
    }

    private static void check(String what, boolean ok) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) {
            failures++;
        }
    }
}
