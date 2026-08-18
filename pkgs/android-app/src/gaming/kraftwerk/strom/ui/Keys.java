package gaming.kraftwerk.strom.ui;

import android.view.KeyEvent;

/**
 * The pad mapping, in one place so a button cannot mean two things on two
 * screens.
 *
 * <p>Every action is claimed by both a pad button and a keyboard key: the
 * device has a physical pad, but it is also driven over adb
 * ({@code input keyevent}) and occasionally from a bluetooth keyboard, and
 * a UI that only answers to one of those is untestable.
 *
 * <p>Face buttons are matched twice on purpose. Some pads report their
 * lower face button as {@code BUTTON_A} and others as {@code DPAD_CENTER},
 * and the right face button frequently arrives as the system BACK key,
 * which is also what the on-screen gesture sends.
 */
public final class Keys {
    public static final int NONE = 0;
    public static final int LEFT = 1;
    public static final int RIGHT = 2;
    public static final int UP = 3;
    public static final int DOWN = 4;

    private Keys() {
    }

    /** Which way a key wants to move, or {@link #NONE}. */
    public static int direction(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
            case KeyEvent.KEYCODE_A:
                return LEFT;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
            case KeyEvent.KEYCODE_D:
                return RIGHT;
            case KeyEvent.KEYCODE_DPAD_UP:
            case KeyEvent.KEYCODE_W:
                return UP;
            case KeyEvent.KEYCODE_DPAD_DOWN:
            case KeyEvent.KEYCODE_S:
                return DOWN;
            default:
                return NONE;
        }
    }

    /** Do the thing under the selection. */
    public static boolean accept(int code) {
        return commit(code) || code == KeyEvent.KEYCODE_SPACE;
    }

    /**
     * Finish editing a text field.
     *
     * <p>Narrower than {@link #accept} on purpose: space is a character
     * somebody is typing into the filter, not a request to leave it.
     */
    public static boolean commit(int code) {
        return code == KeyEvent.KEYCODE_BUTTON_A
            || code == KeyEvent.KEYCODE_DPAD_CENTER
            || code == KeyEvent.KEYCODE_ENTER
            || code == KeyEvent.KEYCODE_NUMPAD_ENTER;
    }

    /** Leave this screen. */
    public static boolean back(int code) {
        return code == KeyEvent.KEYCODE_BUTTON_B
            || code == KeyEvent.KEYCODE_BACK
            || code == KeyEvent.KEYCODE_ESCAPE;
    }

    /** Open the selected game's own screen at its options. */
    public static boolean options(int code) {
        return code == KeyEvent.KEYCODE_BUTTON_X
            || code == KeyEvent.KEYCODE_BUTTON_Y
            || code == KeyEvent.KEYCODE_C;
    }

    /** Reach the app's settings, from anywhere, in one press. */
    public static boolean shoulder(int code) {
        return code == KeyEvent.KEYCODE_BUTTON_L1
            || code == KeyEvent.KEYCODE_BUTTON_R1
            || code == KeyEvent.KEYCODE_MENU;
    }
}
