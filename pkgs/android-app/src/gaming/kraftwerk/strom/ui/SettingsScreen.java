package gaming.kraftwerk.strom.ui;

import android.content.Context;
import android.graphics.Color;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/**
 * Where the catalog comes from and where payload bytes come from.
 *
 * <p>These two fields used to be the first thing on screen, above the game
 * list, which is backwards: they are set once per install and read never.
 * They live here, one shoulder press from the grid, and the keys they are
 * stored under are unchanged ({@code catalog-url},
 * {@code private-gateway}), because {@code LaunchActivity} reads the same
 * two when it is driven over adb.
 */
public final class SettingsScreen extends LinearLayout implements Screen {
    private final Theme t;
    private final Host host;
    private final CoverCache covers;

    private final EditText remote;
    private final EditText gateway;
    private final LinearLayout rowBox;
    private final TextView status;
    private final List<Row> rows = new ArrayList<Row>();
    private int sel;

    public SettingsScreen(Context c, Theme theme, Host host, CoverCache covers) {
        super(c);
        this.t = theme;
        this.host = host;
        this.covers = covers;
        setOrientation(VERTICAL);
        setPadding(t.pad, t.pad, t.pad, t.pad);

        TextView title = t.text(c, t.big, Theme.ACCENT);
        title.setText("Settings");
        addView(title);

        // Built before the rows because a row's action writes to it.
        status = t.text(c, t.small, Theme.WARN);

        rowBox = new LinearLayout(c);
        rowBox.setOrientation(VERTICAL);
        rowBox.setPadding(0, t.gap, 0, 0);
        addView(rowBox, new LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f));

        remote = field(c, host.catalogUrl(),
            "radicle seed, or an http server serving /games");
        remote.addTextChangedListener(new TextWatcher() {
            @Override
            public void afterTextChanged(Editable e) {
                // Stored as it is typed, so a player who edits it and walks
                // away with the pad has not lost the edit. Nothing is
                // fetched until Reload.
                host.setCatalogUrl(e.toString().trim());
            }

            @Override
            public void beforeTextChanged(CharSequence s, int a, int b, int d) {
            }

            @Override
            public void onTextChanged(CharSequence s, int a, int b, int d) {
            }
        });

        gateway = field(c, host.gateway(), "http://host:8080");
        gateway.addTextChangedListener(new TextWatcher() {
            @Override
            public void afterTextChanged(Editable e) {
                host.setGateway(e.toString().trim());
            }

            @Override
            public void beforeTextChanged(CharSequence s, int a, int b, int d) {
            }

            @Override
            public void onTextChanged(CharSequence s, int a, int b, int d) {
            }
        });

        add(new Row("Remote",
            "where the catalog is read from; append #<commit> to pin a revision",
            remote, null));
        // Same idea as STROM_IPFS_GATEWAYS on the desktop: a private or LAN
        // mirror is tried first and the public gateways stay as the
        // fallback. Safe to point anywhere, because the CID is the only
        // trusted input -- a gateway that answers with the wrong bytes fails
        // DAG verification and the next one gets a turn.
        add(new Row("Private gateway",
            "tried before the public gateways; optional",
            gateway, null));
        add(new Row("Reload catalog", "re-reads every game from the remote", null,
            new Runnable() {
                @Override
                public void run() {
                    host.reloadCatalog();
                    host.backToGrid();
                }
            }));
        add(new Row("Forget downloaded cover art",
            "the grid refetches art as you scroll; game payloads are untouched",
            null,
            new Runnable() {
                @Override
                public void run() {
                    covers.clear();
                    status.setText("cover art forgotten");
                }
            }));

        addView(status);

        TextView legend = t.text(c, t.small, Theme.DIM);
        legend.setPadding(0, t.gap, 0, 0);
        legend.setText("A  edit or run      B  back to the grid");
        addView(legend);

        refresh();
    }

    private EditText field(Context c, String value, String hint) {
        EditText f = new EditText(c);
        f.setSingleLine(true);
        f.setInputType(InputType.TYPE_TEXT_VARIATION_URI);
        f.setHint(hint);
        f.setText(value);
        f.setTextSize(TypedValue.COMPLEX_UNIT_PX, t.small);
        f.setTextColor(Theme.TEXT);
        f.setHintTextColor(Theme.DIM);
        // Focusable only while being edited; see Theme.startEditing.
        f.setFocusable(false);
        f.setFocusableInTouchMode(false);
        Theme.commitOnDone(f);
        return f;
    }

    private static final class Row {
        final String label;
        final String note;
        final EditText field;
        final Runnable action;
        View box;
        TextView labelView;
        TextView noteView;

        Row(String label, String note, EditText field, Runnable action) {
            this.label = label;
            this.note = note;
            this.field = field;
            this.action = action;
        }
    }

    private void add(final Row r) {
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
        r.labelView = t.text(c, t.body, Theme.TEXT);
        r.labelView.setText(r.label);
        line.addView(r.labelView, new LayoutParams(LayoutParams.WRAP_CONTENT,
            LayoutParams.WRAP_CONTENT));
        if (r.field != null) {
            LayoutParams grow = new LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f);
            grow.leftMargin = t.pad;
            line.addView(r.field, grow);
        }
        box.addView(line, new LayoutParams(LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT));

        r.noteView = t.text(c, t.small, Theme.DIM);
        r.noteView.setText(r.note);
        box.addView(r.noteView);

        box.setOnClickListener(new OnClickListener() {
            @Override
            public void onClick(View v) {
                sel = rows.indexOf(r);
                refresh();
                activate();
            }
        });

        r.box = box;
        rows.add(r);
        rowBox.addView(box);
    }

    // ---- input -----------------------------------------------------------

    @Override
    public void onShown() {
        status.setText("");
        refresh();
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
        if (Keys.back(code) || Keys.shoulder(code)) {
            host.backToGrid();
            return true;
        }
        return false;
    }

    @Override
    public void onDirection(int dir) {
        if (dir == Keys.UP) {
            sel = Math.max(0, sel - 1);
            refresh();
        } else if (dir == Keys.DOWN) {
            sel = Math.min(rows.size() - 1, sel + 1);
            refresh();
        }
    }

    private void activate() {
        Row r = (sel >= 0 && sel < rows.size()) ? rows.get(sel) : null;
        if (r == null) {
            return;
        }
        if (r.field != null) {
            Theme.startEditing(r.field);
        } else if (r.action != null) {
            r.action.run();
        }
    }

    private void refresh() {
        for (int i = 0; i < rows.size(); i++) {
            Row r = rows.get(i);
            boolean on = i == sel;
            r.box.setBackground(on
                ? Theme.rowPlate(t.radius, t.stroke)
                : Theme.plate(Color.argb(28, 255, 255, 255), Color.TRANSPARENT, 0, t.radius));
            r.labelView.setTextColor(on ? Theme.TEXT : Theme.DIM);
        }
    }
}
