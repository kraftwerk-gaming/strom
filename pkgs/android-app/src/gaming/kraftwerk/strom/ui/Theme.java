package gaming.kraftwerk.strom.ui;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.TextView;

/**
 * Colours and metrics for the couch UI, in one place.
 *
 * <p>The palette and the proportions are the desktop couch launcher's
 * ({@code pkgs/launcher/launcher.py}), so a player who knows one recognises
 * the other. Every size is derived from the panel's short side rather than
 * fixed in pixels: this device has two panels of different sizes, and the
 * same code has to be legible on both from arm's length.
 *
 * <p>There is no {@code res/} tree in this APK, which is why colours and
 * sizes are Java constants and every drawable is built by hand.
 */
public final class Theme {
    public static final int BG_TOP = Color.rgb(12, 14, 24);
    public static final int BG_BOTTOM = Color.rgb(24, 18, 38);
    public static final int ACCENT = Color.rgb(94, 211, 255);
    public static final int TEXT = Color.rgb(235, 238, 245);
    public static final int DIM = Color.rgb(130, 135, 150);
    /** A row that exists but cannot be picked. */
    public static final int DEAD = Color.rgb(92, 96, 110);
    public static final int WARN = Color.rgb(226, 160, 70);
    /** Behind a tile whose art has not arrived. */
    public static final int TILE = Color.rgb(26, 28, 40);

    /**
     * Steam's {@code hero} is a 460x215 header and the Lutris banner is
     * 460x215 too, so that is the shape the grid is laid out for; the
     * desktop launcher uses the identical aspect for the same reason.
     */
    public static final float TILE_ASPECT = 215f / 460f;

    /** Text sizes in pixels: title, body, and the second line of a row. */
    public final float big;
    public final float body;
    public final float small;
    /** Space between tiles, and the screen's outer margin. */
    public final int gap;
    public final int pad;
    public final int radius;
    public final int stroke;

    public Theme(Context c) {
        DisplayMetrics m = c.getResources().getDisplayMetrics();
        // The short side, so a landscape handheld and a portrait phone both
        // get text scaled to the dimension that actually constrains it.
        int h = Math.min(m.widthPixels, m.heightPixels);
        big = Math.max(24f, h * 0.048f);
        body = Math.max(16f, h * 0.030f);
        small = Math.max(13f, h * 0.023f);
        gap = Math.max(8, Math.round(h * 0.016f));
        pad = Math.max(10, Math.round(h * 0.022f));
        radius = Math.max(4, Math.round(h * 0.009f));
        stroke = Math.max(3, Math.round(h * 0.005f));
    }

    public TextView text(Context c, float sizePx, int color) {
        TextView v = new TextView(c);
        v.setTextSize(TypedValue.COMPLEX_UNIT_PX, sizePx);
        v.setTextColor(color);
        return v;
    }

    /** The window backdrop: the launcher's vertical gradient. */
    public static GradientDrawable background() {
        return new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
            new int[] { BG_TOP, BG_BOTTOM });
    }

    /**
     * A rounded plate, for the selected row or the focus frame on a tile.
     *
     * <p>Returns a fresh drawable every time on purpose: a
     * {@link GradientDrawable} carries the bounds of whatever view it was
     * last drawn in, so sharing one instance across rows makes them fight
     * over its size.
     */
    public static GradientDrawable plate(int fill, int stroke, int strokeWidth, int radius) {
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.RECTANGLE);
        d.setColor(fill);
        d.setCornerRadius(radius);
        if (strokeWidth > 0) {
            d.setStroke(strokeWidth, stroke);
        }
        return d;
    }

    /** The accent wash under the selected row. */
    public static GradientDrawable rowPlate(int radius, int strokeWidth) {
        return plate(Color.argb(46, 94, 211, 255), Color.argb(150, 94, 211, 255),
            strokeWidth, radius);
    }

    // ---- text entry ------------------------------------------------------
    //
    // A field is focusable only while it is being edited. Left permanently
    // focusable, Android's own focus search hands it the d-pad and the
    // selection stops moving; a pad user then cannot leave the field,
    // because a pad has no Tab.

    public static void startEditing(EditText f) {
        f.setFocusable(true);
        f.setFocusableInTouchMode(true);
        f.requestFocus();
        f.setSelection(f.getText().length());
        InputMethodManager im = (InputMethodManager)
            f.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        if (im != null) {
            im.showSoftInput(f, InputMethodManager.SHOW_IMPLICIT);
        }
    }

    public static void stopEditing(EditText f) {
        InputMethodManager im = (InputMethodManager)
            f.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        if (im != null) {
            im.hideSoftInputFromWindow(f.getWindowToken(), 0);
        }
        f.clearFocus();
        f.setFocusable(false);
        f.setFocusableInTouchMode(false);
    }

    /**
     * Keep a field usable on a landscape handheld.
     *
     * <p>Two things, both learned on the device. The soft keyboard's Done
     * key must end the edit: dismissing it by touch otherwise leaves the
     * field focused and every subsequent pad press goes on being typing.
     * And {@code IME_FLAG_NO_EXTRACT_UI} is required, because in landscape
     * the IME otherwise takes the whole screen for its own giant copy of
     * the field -- measured on this panel, filtering the grid became typing
     * into a full-screen white box with the grid nowhere in sight.
     */
    public static void commitOnDone(final EditText f) {
        f.setImeOptions(EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        f.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            @Override
            public boolean onEditorAction(TextView v, int actionId, KeyEvent event) {
                stopEditing(f);
                return true;
            }
        });
    }
}
