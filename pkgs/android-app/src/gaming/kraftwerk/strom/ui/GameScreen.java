package gaming.kraftwerk.strom.ui;

import android.content.Context;
import android.graphics.Color;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import gaming.kraftwerk.strom.Launch;
import gaming.kraftwerk.strom.catalog.Game;
import gaming.kraftwerk.strom.catalog.Layer;
import gaming.kraftwerk.strom.catalog.Options;
import gaming.kraftwerk.strom.catalog.Setting;
import gaming.kraftwerk.strom.runtime.Handoff;
import gaming.kraftwerk.strom.runtime.RuntimeInstaller;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * One game: its art, what it is, what it will cost, and the rows that act
 * on it.
 *
 * <p>The options rows are the desktop launcher's per-game customize view
 * (its {@code settings_view}) and the flat list this replaces: one row per
 * published setting, a bool toggling and an enum cycling. The rules for
 * what may be offered are not restated here -- they live in
 * {@link Options}, which is shared with the launcher's manifest and tested
 * on the plain JDK, so a row cannot drift from what a game accepts.
 *
 * <p>Play, the runtime-install offer and the payload reset are rows in the
 * same list as the options, because on a pad they are all "the thing under
 * the selection" and a player should not have to find a differently shaped
 * control for each.
 */
public final class GameScreen extends LinearLayout implements Screen {
    private static final int KIND_PLAY = 0;
    private static final int KIND_OPTION = 1;
    private static final int KIND_RESET = 2;

    private final Theme t;
    private final Host host;
    private final CoverCache covers;

    private final ImageView art;
    private final TextView title;
    private final TextView meta;
    private final TextView blurb;
    private final TextView status;
    private final ScrollView rowScroll;
    private final LinearLayout rowBox;
    private final TextView totals;

    private Game game;
    private Map<String, String> picks = new LinkedHashMap<String, String>();
    private final List<Row> rows = new ArrayList<Row>();
    private int sel;
    /** A launch or an install is in flight; a second press must not start another. */
    private boolean busy;
    /** Play asked for the payload to be deleted before the picks can hold. */
    private boolean offerReset;
    private int artW;
    private int artH;

    public GameScreen(Context c, Theme theme, Host host, CoverCache covers) {
        super(c);
        this.t = theme;
        this.host = host;
        this.covers = covers;
        setOrientation(HORIZONTAL);

        // Landscape first: art and prose on the left, the rows the pad drives
        // on the right, both full height. A 1920x1080 handheld panel is the
        // shape this is drawn for.
        LinearLayout left = new LinearLayout(c);
        left.setOrientation(VERTICAL);
        left.setPadding(t.pad, t.pad, t.pad, t.pad);

        art = new ImageView(c);
        art.setScaleType(ImageView.ScaleType.CENTER_CROP);
        art.setBackgroundColor(Theme.TILE);
        left.addView(art, new LayoutParams(LayoutParams.MATCH_PARENT, 1));

        title = t.text(c, t.big, Theme.TEXT);
        title.setPadding(0, t.gap, 0, 0);
        left.addView(title);

        meta = t.text(c, t.small, Theme.DIM);
        left.addView(meta);

        blurb = t.text(c, t.small, Theme.DIM);
        blurb.setMaxLines(4);
        blurb.setPadding(0, t.gap / 2, 0, 0);
        left.addView(blurb);

        // The launch's own words: what Launch.Progress says while it works,
        // and what its Outcome says when it stops. Sized like body text and
        // given four lines, because a NEEDS_SETUP message is an instruction
        // the player has to be able to read and act on.
        status = t.text(c, t.body, Theme.ACCENT);
        status.setMaxLines(4);
        status.setPadding(0, t.gap, 0, 0);
        left.addView(status);

        LinearLayout right = new LinearLayout(c);
        right.setOrientation(VERTICAL);
        right.setPadding(t.pad, t.pad, t.pad, t.pad);

        rowBox = new LinearLayout(c);
        rowBox.setOrientation(VERTICAL);
        rowScroll = new ScrollView(c);
        rowScroll.setFocusable(false);
        // FrameLayout params, not this class's LinearLayout ones: ScrollView
        // is a FrameLayout and casts its child's params to that type.
        rowScroll.addView(rowBox, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT));
        right.addView(rowScroll, new LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f));

        totals = t.text(c, t.small, Theme.DIM);
        totals.setPadding(0, t.gap, 0, 0);
        right.addView(totals);

        TextView legend = t.text(c, t.small, Theme.DIM);
        legend.setPadding(0, t.gap, 0, 0);
        legend.setText("A  do it      left / right  change      X  defaults"
            + "      B  back      L1 / R1  settings");
        right.addView(legend);

        addView(left, new LayoutParams(0, LayoutParams.MATCH_PARENT, 1.1f));
        addView(right, new LayoutParams(0, LayoutParams.MATCH_PARENT, 1f));
    }

    // ---- contents --------------------------------------------------------

    public void setGame(Game g, boolean atOptions) {
        game = g;
        picks = host.picks(g);
        busy = false;
        offerReset = false;
        status.setText("");
        title.setText(g.title());
        meta.setText("runtime " + g.runtime + "      backend " + g.backend
            + "      " + g.slug);
        blurb.setText(g.description == null ? "" : g.description);
        blurb.setVisibility(g.description == null ? GONE : VISIBLE);
        applyArt();
        buildRows();
        // The options button opens this screen on the first option rather
        // than on Play, so one press lands where it was aimed.
        sel = (atOptions && rows.size() > 1) ? 1 : 0;
        refresh();
    }

    public Game game() {
        return game;
    }

    /** A line from {@code Launch.Progress}, or an {@code Outcome} message. */
    public void say(String s) {
        status.setText(s);
    }

    public void setBusy(boolean b) {
        busy = b;
        buildRows();
    }

    /**
     * Offer to delete the payload.
     *
     * <p>Turning a mod back off cannot be done by unpacking anything, so the
     * only honest answer is to fetch the game again; the base is gigabytes,
     * so it is a row the player has to choose, shown only once a pick
     * actually needs it.
     */
    public void offerReset(boolean b) {
        offerReset = b;
        buildRows();
    }

    /** Re-evaluate every row: a runtime app may have been installed since. */
    public void refreshRows() {
        if (game != null) {
            buildRows();
        }
    }

    @Override
    protected void onSizeChanged(int w, int h, int ow, int oh) {
        super.onSizeChanged(w, h, ow, oh);
        // Matches the 1.1 : 1 weight split above; the cover is cropped to
        // exactly this, so it has to be recomputed when the panel changes.
        artW = Math.max(1, Math.round(w * 0.524f) - 2 * t.pad);
        artH = Math.max(1, Math.round(artW * Theme.TILE_ASPECT));
        LayoutParams lp = (LayoutParams) art.getLayoutParams();
        lp.height = artH;
        art.setLayoutParams(lp);
        applyArt();
    }

    private void applyArt() {
        if (game != null && artW > 0) {
            covers.into(game.art(), art, artW, artH);
        }
    }

    // ---- rows ------------------------------------------------------------

    private static final class Row {
        final int kind;
        final Setting setting;
        View box;
        TextView label;
        TextView value;
        TextView note;
        boolean live;

        Row(int kind, Setting setting) {
            this.kind = kind;
            this.setting = setting;
        }
    }

    /**
     * Rebuilt whole rather than mutated, because a pick changes what its
     * neighbours may offer: a parent switch going off takes the option that
     * depends on it with it.
     */
    private void buildRows() {
        rows.clear();
        rowBox.removeAllViews();
        rows.add(new Row(KIND_PLAY, null));
        for (Setting s : game.settings) {
            rows.add(new Row(KIND_OPTION, s));
        }
        if (offerReset) {
            rows.add(new Row(KIND_RESET, null));
        }
        for (Row r : rows) {
            rowBox.addView(build(r));
        }
        if (sel >= rows.size()) {
            sel = rows.size() - 1;
        }
        // Counted, not just summed: a manifest may publish a layer without a
        // size, and "no mods selected" would then be a lie about a download
        // that is about to happen.
        List<Layer> chosen = Options.select(game, picks);
        long extra = Options.bytes(chosen);
        totals.setText(game.settings.isEmpty()
            ? "this game publishes no options"
            : (chosen.isEmpty()
                ? "no mods selected"
                : chosen.size() + " mod layer(s) selected"
                    + (extra > 0 ? ", " + Launch.human(extra) + " to download" : "")));
        refresh();
    }

    private View build(Row r) {
        Context c = getContext();
        LinearLayout box = new LinearLayout(c);
        box.setOrientation(VERTICAL);
        box.setPadding(t.pad / 2, t.gap / 2, t.pad / 2, t.gap / 2);
        LayoutParams outer = new LayoutParams(LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT);
        outer.bottomMargin = t.gap / 2;
        box.setLayoutParams(outer);

        LinearLayout line = new LinearLayout(c);
        line.setOrientation(HORIZONTAL);
        line.setGravity(Gravity.CENTER_VERTICAL);

        r.label = t.text(c, t.body, Theme.TEXT);
        line.addView(r.label, new LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f));

        r.value = t.text(c, t.body, Theme.TEXT);
        r.value.setGravity(Gravity.END);
        line.addView(r.value);

        box.addView(line, new LayoutParams(LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT));

        r.note = t.text(c, t.small, Theme.DIM);
        r.note.setMaxLines(3);
        box.addView(r.note);

        // Touch reaches the same actions the pad does.
        final Row target = r;
        box.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                sel = rows.indexOf(target);
                refresh();
                activate();
            }
        });

        r.box = box;
        fill(r);
        return box;
    }

    /** A row's text and whether it may be acted on. */
    private void fill(Row r) {
        if (r.kind == KIND_PLAY) {
            fillPlay(r);
            return;
        }
        if (r.kind == KIND_RESET) {
            r.label.setText("Delete this download and start over");
            r.value.setText("");
            r.note.setText("the only way to remove a mod layer already unpacked");
            r.live = !busy;
            return;
        }
        Setting s = r.setting;
        String off = Options.unavailable(game, s, picks);
        String current = Options.value(s, picks);
        r.label.setText(s.title());
        // A star marks a pick that differs from what the game ships with,
        // the same mark the desktop launcher's rows carry.
        r.value.setText(current + (current.equals(s.defaultValue) ? "" : " *"));
        r.note.setText(off != null ? off : detail(game, s, current, picks));
        // A pick that could not be honoured must not be pickable at all; the
        // line underneath says which reason it is.
        r.live = off == null;
    }

    private void fillPlay(Row r) {
        boolean installed = Handoff.available(getContext(), game);
        String offer = RuntimeInstaller.offerLabel(game);
        r.value.setText(busy ? "working" : "");
        if (!game.isPlayable()) {
            r.label.setText("Not published for Android");
            r.note.setText(game.payloadCid == null
                ? "no payload CID in metadata.json"
                : "backend '" + game.backend + "' unsupported");
            r.live = false;
        } else if (!installed && offer != null) {
            // The runtime is missing but we have a pinned build of it, so
            // offer that rather than telling someone to go and find an APK.
            r.label.setText("Install " + offer);
            r.note.setText(Launch.human(RuntimeInstaller.offerSize(game))
                + " download, then Play");
            r.live = !busy;
        } else if (!installed) {
            r.label.setText("Runtime app not installed");
            r.note.setText("nothing pinned for backend '" + game.backend + "'");
            r.live = false;
        } else {
            r.label.setText("Play");
            r.note.setText(host.downloaded(game)
                ? "already downloaded"
                : "downloads on first launch");
            r.live = !busy;
        }
    }

    /**
     * An offered row's second line: what this value costs, and what it does.
     *
     * <p>The size comes FIRST. Measured on the device: a help paragraph is
     * several lines long, the row clamps it, and a size appended after it is
     * exactly the part that gets cut off -- while it is the part that
     * decides whether the player wants the download at all.
     */
    private static String detail(Game g, Setting s, String current, Map<String, String> picks) {
        String help = (s.help == null) ? "" : s.help;
        long size = Options.bytes(Options.wouldSelect(g, s, current, picks));
        return size > 0 ? "+" + Launch.human(size) + " to download.  " + help : help;
    }

    private void refresh() {
        for (int i = 0; i < rows.size(); i++) {
            Row r = rows.get(i);
            boolean on = i == sel;
            r.box.setBackground(on
                ? Theme.rowPlate(t.radius, t.stroke)
                : Theme.plate(Color.argb(28, 255, 255, 255), Color.TRANSPARENT, 0, t.radius));
            int color = r.live ? (on ? Theme.TEXT : Theme.DIM) : Theme.DEAD;
            r.label.setTextColor(color);
            r.value.setTextColor(r.live ? (on ? Theme.ACCENT : Theme.DIM) : Theme.DEAD);
            r.note.setTextColor(r.live ? Theme.DIM : Theme.DEAD);
        }
        reveal();
    }

    private void reveal() {
        if (sel < 0 || sel >= rows.size()) {
            return;
        }
        final View box = rows.get(sel).box;
        rowScroll.post(new Runnable() {
            @Override
            public void run() {
                int top = box.getTop();
                int bottom = top + box.getHeight();
                int y = rowScroll.getScrollY();
                int h = rowScroll.getHeight();
                if (top < y || bottom > y + h) {
                    rowScroll.smoothScrollTo(0, Math.max(0, top - h / 3));
                }
            }
        });
    }

    // ---- input -----------------------------------------------------------

    @Override
    public void onShown() {
        // A runtime app may have been installed, or a payload deleted, while
        // another app was in front.
        refreshRows();
    }

    @Override
    public boolean onPadKey(int code) {
        int d = Keys.direction(code);
        if (d != Keys.NONE) {
            onDirection(d);
            return true;
        }
        if (Keys.accept(code)) {
            activate();
            return true;
        }
        if (Keys.back(code)) {
            host.backToGrid();
            return true;
        }
        // X is "back to the shipped values", as it is in the desktop
        // launcher's options view. Y is left alone: the grid uses both to
        // get here, and a stray Y on arrival must not change anything.
        if (code == KeyEvent.KEYCODE_BUTTON_X && game != null && !game.settings.isEmpty()) {
            defaults();
            return true;
        }
        if (Keys.shoulder(code)) {
            host.openSettings();
            return true;
        }
        return false;
    }

    @Override
    public void onDirection(int dir) {
        switch (dir) {
            case Keys.UP:
                sel = Math.max(0, sel - 1);
                refresh();
                break;
            case Keys.DOWN:
                sel = Math.min(rows.size() - 1, sel + 1);
                refresh();
                break;
            case Keys.LEFT:
                cycle(-1);
                break;
            case Keys.RIGHT:
                cycle(1);
                break;
            default:
                break;
        }
    }

    private void activate() {
        Row r = (sel >= 0 && sel < rows.size()) ? rows.get(sel) : null;
        if (r == null || !r.live) {
            return;
        }
        if (r.kind == KIND_OPTION) {
            cycle(1);
            return;
        }
        if (r.kind == KIND_RESET) {
            host.resetPayload(game);
            return;
        }
        // Re-check rather than trusting what the row was built with: the
        // user may have installed the runtime since, from here or elsewhere.
        if (!Handoff.available(getContext(), game)) {
            host.installRuntime(game);
        } else {
            host.play(game);
        }
    }

    private void cycle(int step) {
        Row r = (sel >= 0 && sel < rows.size()) ? rows.get(sel) : null;
        if (r == null || r.kind != KIND_OPTION || !r.live) {
            return;
        }
        Setting s = r.setting;
        List<String> usable = Options.selectable(game, s, picks);
        if (usable.size() < 2) {
            return;
        }
        String current = Options.value(s, picks);
        int at = usable.indexOf(current);
        if (at < 0) {
            at = 0;
        }
        int next = ((at + step) % usable.size() + usable.size()) % usable.size();
        picks.put(s.key, usable.get(next));
        host.savePicks(game, picks);
        // Whatever the picks were when the offer to delete this download
        // appeared, they have just changed; Play works out again whether it
        // is still the only way forward.
        offerReset = false;
        buildRows();
    }

    private void defaults() {
        picks.clear();
        host.savePicks(game, picks);
        offerReset = false;
        buildRows();
    }
}
