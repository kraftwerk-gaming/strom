package gaming.kraftwerk.strom.ui;

import android.content.Context;
import android.graphics.Color;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AbsListView;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.GridView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import gaming.kraftwerk.strom.catalog.Game;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * The first screen: a grid of cover art, a filter, and a status line.
 *
 * <p>Shaped after the desktop couch launcher's overview. What differs is
 * only what has to: the launcher draws its grid itself in pygame, and here
 * a {@link GridView} does the recycling, because the catalog is hundreds of
 * games and inflating a view per game janks the UI thread for seconds (the
 * flat list this replaces capped itself at 60 rows for exactly that
 * reason, and then told the player to filter).
 *
 * <p>The grid is deliberately NOT focusable. Android's focus search moves
 * by geometry and cannot be told that the top row of a grid should reach
 * the filter, so the selection is ours: one index, moved by
 * {@link #onPadKey}, drawn as a frame on the chosen tile. Touch still
 * works, through the item click listener.
 */
public final class GameGrid extends LinearLayout implements Screen {
    /** The header cells, left to right, reached by pressing up from the grid. */
    private static final int CHROME_NONE = -1;
    private static final int CHROME_FILTER = 0;
    private static final int CHROME_SCOPE = 1;
    private static final int CHROME_SETTINGS = 2;
    private static final int CHROME_LAST = CHROME_SETTINGS;

    private final Theme t;
    private final Host host;
    private final CoverCache covers;

    private final EditText filter;
    private final TextView scopeChip;
    private final TextView settingsChip;
    private final TextView status;
    private final GridView grid;
    private final Tiles tiles;

    private List<Game> all = Collections.emptyList();
    private final List<Game> shown = new ArrayList<Game>();
    /**
     * Whether to list games this device cannot run. Off by default: most of
     * the catalog is PC titles with no Android payload, and leaving them in
     * buries the handful that do run.
     */
    private boolean showAll;
    private int sel;
    private int chrome = CHROME_NONE;
    private int cols = 4;
    private int tileW;
    private int tileH;

    public GameGrid(Context c, Theme theme, Host host, CoverCache covers) {
        super(c);
        this.t = theme;
        this.host = host;
        this.covers = covers;
        setOrientation(VERTICAL);
        setPadding(0, t.gap, 0, 0);

        LinearLayout head = new LinearLayout(c);
        head.setOrientation(HORIZONTAL);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.setPadding(t.pad, 0, t.pad, 0);

        TextView brand = t.text(c, t.big, Theme.ACCENT);
        brand.setText("STROM");
        brand.setPadding(0, 0, t.pad, 0);
        head.addView(brand);

        filter = new EditText(c);
        filter.setSingleLine(true);
        filter.setHint("filter");
        filter.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, t.body);
        filter.setTextColor(Theme.TEXT);
        filter.setHintTextColor(Theme.DIM);
        filter.setPadding(t.pad / 2, t.gap / 2, t.pad / 2, t.gap / 2);
        // Focusable only while being edited; see Theme.startEditing.
        filter.setFocusable(false);
        filter.setFocusableInTouchMode(false);
        Theme.commitOnDone(filter);
        filter.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                chrome = CHROME_FILTER;
                refresh();
                Theme.startEditing(filter);
            }
        });
        filter.addTextChangedListener(new TextWatcher() {
            @Override
            public void afterTextChanged(Editable e) {
                rebuild(true);
            }

            @Override
            public void beforeTextChanged(CharSequence s, int a, int b, int d) {
            }

            @Override
            public void onTextChanged(CharSequence s, int a, int b, int d) {
            }
        });
        LayoutParams grow = new LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f);
        head.addView(filter, grow);

        scopeChip = chip(c, "Playable only");
        scopeChip.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                chrome = CHROME_SCOPE;
                toggleScope();
            }
        });
        head.addView(scopeChip);

        settingsChip = chip(c, "Settings");
        settingsChip.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                host.openSettings();
            }
        });
        head.addView(settingsChip);

        addView(head, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));

        status = t.text(c, t.small, Theme.DIM);
        status.setPadding(t.pad, t.gap / 2, t.pad, t.gap / 2);
        status.setText("loading catalog");
        addView(status);

        tiles = new Tiles();
        grid = new GridView(c);
        grid.setAdapter(tiles);
        grid.setNumColumns(cols);
        grid.setHorizontalSpacing(t.gap);
        grid.setVerticalSpacing(t.gap);
        grid.setStretchMode(GridView.STRETCH_COLUMN_WIDTH);
        grid.setPadding(t.pad, t.gap, t.pad, t.gap);
        grid.setScrollBarStyle(View.SCROLLBARS_OUTSIDE_OVERLAY);
        grid.setFocusable(false);
        grid.setFocusableInTouchMode(false);
        grid.setOnItemClickListener(new AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(AdapterView<?> parent, View v, int position, long id) {
                sel = position;
                chrome = CHROME_NONE;
                refresh();
                open(false);
            }
        });
        // Touch shortcut to the same place the options button goes.
        grid.setOnItemLongClickListener(new AdapterView.OnItemLongClickListener() {
            @Override
            public boolean onItemLongClick(AdapterView<?> parent, View v, int position, long id) {
                sel = position;
                chrome = CHROME_NONE;
                refresh();
                open(true);
                return true;
            }
        });
        addView(grid, new LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f));

        TextView legend = t.text(c, t.small, Theme.DIM);
        legend.setPadding(t.pad, 0, t.pad, t.gap);
        legend.setText("D-pad / stick  move      A  play      X / Y  options"
            + "      up  filter row      L1 / R1  settings      B  quit");
        addView(legend);
    }

    private TextView chip(Context c, String label) {
        TextView v = t.text(c, t.small, Theme.DIM);
        v.setText(label);
        v.setPadding(t.pad / 2, t.gap / 2, t.pad / 2, t.gap / 2);
        LayoutParams lp = new LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT);
        lp.leftMargin = t.gap;
        v.setLayoutParams(lp);
        return v;
    }

    // ---- data ------------------------------------------------------------

    public void setGames(List<Game> games) {
        all = games;
        rebuild(true);
    }

    /** Said while the catalog is loading, or when loading it failed. */
    public void setStatus(String s) {
        status.setText(s);
    }

    public Game current() {
        return (sel >= 0 && sel < shown.size()) ? shown.get(sel) : null;
    }

    private void rebuild(boolean resetSel) {
        String q = filter.getText().toString().trim().toLowerCase();
        shown.clear();
        int playable = 0;
        for (Game g : all) {
            if (g.isPlayable()) {
                playable++;
            }
        }
        for (Game g : all) {
            if (!showAll && !g.isPlayable()) {
                continue;
            }
            if (!q.isEmpty()
                && !g.title().toLowerCase().contains(q)
                && !g.slug.toLowerCase().contains(q)) {
                continue;
            }
            shown.add(g);
        }
        if (resetSel) {
            sel = 0;
        }
        if (sel >= shown.size()) {
            sel = Math.max(0, shown.size() - 1);
        }
        tiles.notifyDataSetChanged();

        int hidden = showAll ? 0 : all.size() - playable;
        scopeChip.setText(showAll ? "All " + all.size() : "Playable only");
        String summary = playable + " playable"
            + (hidden > 0 ? ", " + hidden + " not published for Android" : "")
            + (q.isEmpty() ? "" : ", " + shown.size() + " matching");
        // A catalog where nothing is playable is the expected result when the
        // seed's canonical head predates the revision that published the
        // games, and public seeds do lag. Saying so beats leaving someone
        // with an empty grid wondering what is broken.
        if (!all.isEmpty() && playable == 0) {
            summary += " -- this seed's master may predate them; try another remote";
        }
        status.setText(all.isEmpty() ? "no games loaded" : summary);
        refresh();
    }

    private void toggleScope() {
        showAll = !showAll;
        rebuild(true);
    }

    // ---- selection -------------------------------------------------------

    @Override
    protected void onSizeChanged(int w, int h, int ow, int oh) {
        super.onSizeChanged(w, h, ow, oh);
        // Columns follow the ASPECT, not the raw width, which is the lesson
        // the desktop launcher's Layout records: keyed off width alone,
        // tiles SHRINK on a bigger panel instead of getting bigger. Four
        // across is the design at 16:9, which is this handheld's panel.
        cols = Math.max(2, Math.min(6, Math.round(4f * (w / (float) h) / (16f / 9f))));
        int usable = w - 2 * t.pad - (cols - 1) * t.gap;
        tileW = Math.max(1, usable / cols);
        tileH = Math.max(1, Math.round(tileW * Theme.TILE_ASPECT));
        grid.setNumColumns(cols);
        tiles.notifyDataSetChanged();
    }

    @Override
    public void onShown() {
        // Coming back from a game or from settings puts the selection back
        // on the tiles. Measured on the device: leaving it parked in the
        // header meant the next A press toggled a chip when the player
        // plainly meant to open the game they were looking at.
        chrome = CHROME_NONE;
        refresh();
    }

    @Override
    public boolean onPadKey(int code) {
        int d = Keys.direction(code);
        if (d != Keys.NONE) {
            onDirection(d);
            return true;
        }
        if (Keys.shoulder(code)) {
            host.openSettings();
            return true;
        }
        if (Keys.accept(code)) {
            if (chrome == CHROME_NONE) {
                open(false);
            } else if (chrome == CHROME_FILTER) {
                Theme.startEditing(filter);
            } else if (chrome == CHROME_SCOPE) {
                toggleScope();
            } else {
                host.openSettings();
            }
            return true;
        }
        if (Keys.options(code)) {
            open(true);
            return true;
        }
        if (Keys.back(code)) {
            if (chrome != CHROME_NONE) {
                chrome = CHROME_NONE;
                refresh();
                return true;
            }
            if (filter.getText().length() > 0) {
                filter.setText("");
                return true;
            }
            host.quit();
            return true;
        }
        return false;
    }

    @Override
    public void onDirection(int dir) {
        if (chrome != CHROME_NONE) {
            switch (dir) {
                case Keys.LEFT:
                    chrome = Math.max(CHROME_FILTER, chrome - 1);
                    break;
                case Keys.RIGHT:
                    chrome = Math.min(CHROME_LAST, chrome + 1);
                    break;
                case Keys.DOWN:
                    chrome = CHROME_NONE;
                    break;
                default:
                    break;
            }
            refresh();
            return;
        }
        int n = shown.size();
        if (n == 0) {
            if (dir == Keys.UP) {
                chrome = CHROME_FILTER;
                refresh();
            }
            return;
        }
        switch (dir) {
            case Keys.LEFT:
                sel = Math.max(0, sel - 1);
                break;
            case Keys.RIGHT:
                sel = Math.min(n - 1, sel + 1);
                break;
            case Keys.DOWN:
                // Clamped to the last game rather than wrapping: a partial
                // bottom row would otherwise swallow the down press.
                sel = Math.min(n - 1, sel + cols);
                break;
            case Keys.UP:
                if (sel >= cols) {
                    sel -= cols;
                } else {
                    chrome = CHROME_FILTER;
                }
                break;
            default:
                break;
        }
        reveal();
        refresh();
    }

    private void open(boolean atOptions) {
        Game g = current();
        if (g != null) {
            host.openGame(g, atOptions);
        }
    }

    /** Keep the chosen tile on screen, with a row of lookahead. */
    private void reveal() {
        int first = grid.getFirstVisiblePosition();
        int last = grid.getLastVisiblePosition();
        if (last <= first) {
            grid.setSelection(sel);
            return;
        }
        if (sel < first + cols) {
            grid.smoothScrollToPosition(Math.max(0, sel - cols));
        } else if (sel > last - cols) {
            grid.smoothScrollToPosition(Math.min(shown.size() - 1, sel + cols));
        }
    }

    /**
     * Repaint what selection looks like.
     *
     * <p>The visible children are updated in place rather than through
     * {@code notifyDataSetChanged}: moving the selection rebinds nothing,
     * and a full rebind on every d-pad press would refetch art requests for
     * a dozen tiles.
     */
    private void refresh() {
        int first = grid.getFirstVisiblePosition();
        for (int i = 0; i < grid.getChildCount(); i++) {
            View v = grid.getChildAt(i);
            if (v instanceof Tile) {
                // Armed only while the selection is on the tiles: two accent
                // frames on screen at once (a tile and a header chip) leaves
                // it ambiguous which one A is about to act on.
                ((Tile) v).setChosen(first + i == sel, chrome == CHROME_NONE);
            }
        }
        paintChip(filter, chrome == CHROME_FILTER);
        paintChip(scopeChip, chrome == CHROME_SCOPE);
        paintChip(settingsChip, chrome == CHROME_SETTINGS);
    }

    private void paintChip(TextView v, boolean on) {
        v.setBackground(on
            ? Theme.rowPlate(t.radius, t.stroke)
            : Theme.plate(Color.argb(40, 255, 255, 255), Theme.DIM, 1, t.radius));
        if (v != filter) {
            v.setTextColor(on ? Theme.TEXT : Theme.DIM);
        }
    }

    // ---- tiles -----------------------------------------------------------

    private final class Tiles extends BaseAdapter {
        @Override
        public int getCount() {
            return shown.size();
        }

        @Override
        public Object getItem(int position) {
            return shown.get(position);
        }

        @Override
        public long getItemId(int position) {
            return position;
        }

        @Override
        public View getView(int position, View reuse, ViewGroup parent) {
            Tile tile = (reuse instanceof Tile) ? (Tile) reuse : new Tile(getContext(), t);
            tile.setLayoutParams(new AbsListView.LayoutParams(
                AbsListView.LayoutParams.MATCH_PARENT, tileH));
            // Art is requested here and nowhere else, so a tile that is
            // never scrolled to never costs a byte.
            tile.bind(shown.get(position), position == sel, chrome == CHROME_NONE,
                covers, tileW, tileH);
            return tile;
        }
    }

    /**
     * One game: its cover art with the title over the bottom of it.
     *
     * <p>The title is always drawn, not only when art is missing. It is the
     * fallback for the hundreds of games whose art has not arrived yet or
     * does not exist, and on a tile that does have art it is what makes the
     * grid readable at a glance rather than a wall of unlabelled pictures.
     */
    static final class Tile extends FrameLayout {
        private final ImageView art;
        private final TextView label;
        private final int radius;
        private final int stroke;
        /** Whether this game has an Android payload, for the dim state. */
        private boolean playable = true;

        Tile(Context c, Theme t) {
            super(c);
            radius = t.radius;
            stroke = t.stroke;
            art = new ImageView(c);
            art.setScaleType(ImageView.ScaleType.CENTER_CROP);
            addView(art, new LayoutParams(LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT));

            label = t.text(c, t.small, Theme.TEXT);
            label.setMaxLines(2);
            label.setEllipsize(TextUtils.TruncateAt.END);
            label.setBackgroundColor(Color.argb(200, 0, 0, 0));
            label.setPadding(t.gap / 2, t.gap / 4, t.gap / 2, t.gap / 4);
            LayoutParams lp = new LayoutParams(LayoutParams.MATCH_PARENT,
                LayoutParams.WRAP_CONTENT);
            lp.gravity = Gravity.BOTTOM;
            addView(label, lp);
        }

        void bind(Game g, boolean chosen, boolean armed, CoverCache covers, int w, int h) {
            label.setText(g.title());
            // A tint derived from the slug, so tiles without art are still
            // distinguishable from each other while they load.
            art.setBackgroundColor(tint(g.slug));
            covers.into(g.art(), art, w, h);
            playable = g.isPlayable();
            setChosen(chosen, armed);
        }

        /**
         * The focus frame.
         *
         * <p>A frame rather than a scale-up: {@code GridView} clips its
         * children to its content box, so a tile in the first or last
         * visible row would have the grown edge (and the frame with it) cut
         * off, which is precisely when the player needs to see it.
         *
         * @param armed whether the grid, rather than the header row, is what
         *              the buttons currently act on
         */
        void setChosen(boolean on, boolean armed) {
            setForeground(on
                ? Theme.plate(Color.TRANSPARENT, armed ? Theme.ACCENT : Theme.DEAD,
                    stroke, radius)
                : null);
            label.setTextColor(on ? Theme.TEXT : Theme.DIM);
            // A game with no Android payload reads as unavailable from the
            // grid rather than only once its own screen is open.
            setAlpha(on ? (playable ? 1f : 0.62f) : (playable ? 0.74f : 0.42f));
        }

        private static int tint(String slug) {
            float hue = Math.abs(slug.hashCode() % 360);
            return Color.HSVToColor(new float[] { hue, 0.30f, 0.22f });
        }
    }
}
