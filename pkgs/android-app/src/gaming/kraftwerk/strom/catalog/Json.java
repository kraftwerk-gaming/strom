package gaming.kraftwerk.strom.catalog;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * A small strict JSON reader.
 *
 * <p>Android ships {@code org.json}, which is deliberately not used: it is
 * lenient in ways that quietly accept malformed input, and a catalog entry
 * that is subtly wrong should fail loudly rather than produce a game that
 * misbehaves later on a phone.
 */
public final class Json {
    private final String s;
    private int i;

    private Json(String s) {
        this.s = s;
    }

    /**
     * @return nested {@link Map}/{@link List}/String/Double/Boolean, or null
     */
    public static Object parse(String text) throws IOException {
        Json p = new Json(text);
        p.ws();
        Object v = p.value();
        p.ws();
        if (p.i != text.length()) {
            throw p.fail("trailing content");
        }
        return v;
    }

    // ---- convenience -----------------------------------------------------
    // The catalog is mostly optional keys, so these return null rather than
    // throwing on a missing or wrongly-typed step. That keeps the calling
    // code free of instanceof ladders.

    /** Walk nested maps; null if any step is missing or not a map. */
    public static Object path(Object root, String... keys) {
        Object cur = root;
        for (String k : keys) {
            if (!(cur instanceof Map)) {
                return null;
            }
            cur = ((Map<?, ?>) cur).get(k);
        }
        return cur;
    }

    /** A string at a path, or null. Non-strings (numbers, maps) yield null. */
    public static String str(Object root, String... keys) {
        Object v = path(root, keys);
        return (v instanceof String) ? (String) v : null;
    }

    /**
     * A scalar at a path as text: strings pass through, booleans and whole
     * numbers stringify. null if missing or a container.
     *
     * <p>The manifest types a value naturally -- an option's bool default is
     * JSON {@code false}, an enum's is a string -- while a player's pick is
     * one comparable type, and this is where the two meet.
     */
    public static String scalar(Object root, String... keys) {
        Object v = path(root, keys);
        if (v instanceof String) {
            return (String) v;
        }
        if (v instanceof Boolean) {
            return v.toString();
        }
        if (v instanceof Double) {
            double d = ((Double) v).doubleValue();
            return (d == Math.rint(d) && !Double.isInfinite(d))
                ? Long.toString((long) d) : Double.toString(d);
        }
        return null;
    }

    /** A number at a path, or {@code fallback} if missing or not a number. */
    public static long num(Object root, long fallback, String... keys) {
        Object v = path(root, keys);
        return (v instanceof Double) ? ((Double) v).longValue() : fallback;
    }

    /** An array at a path; empty when missing or not an array. */
    public static List<?> list(Object root, String... keys) {
        Object v = path(root, keys);
        return (v instanceof List) ? (List<?>) v : Collections.emptyList();
    }

    // ---- parser ----------------------------------------------------------

    private Object value() throws IOException {
        if (i >= s.length()) {
            throw fail("unexpected end of input");
        }
        char c = s.charAt(i);
        switch (c) {
            case '{':
                return object();
            case '[':
                return array();
            case '"':
                return string();
            case 't':
                literal("true");
                return Boolean.TRUE;
            case 'f':
                literal("false");
                return Boolean.FALSE;
            case 'n':
                literal("null");
                return null;
            default:
                return number();
        }
    }

    private Map<String, Object> object() throws IOException {
        expect('{');
        Map<String, Object> m = new LinkedHashMap<String, Object>();
        ws();
        if (peek() == '}') {
            i++;
            return m;
        }
        while (true) {
            ws();
            String k = string();
            ws();
            expect(':');
            ws();
            m.put(k, value());
            ws();
            char c = next();
            if (c == '}') {
                return m;
            }
            if (c != ',') {
                throw fail("expected ',' or '}'");
            }
        }
    }

    private List<Object> array() throws IOException {
        expect('[');
        List<Object> l = new ArrayList<Object>();
        ws();
        if (peek() == ']') {
            i++;
            return l;
        }
        while (true) {
            ws();
            l.add(value());
            ws();
            char c = next();
            if (c == ']') {
                return l;
            }
            if (c != ',') {
                throw fail("expected ',' or ']'");
            }
        }
    }

    private String string() throws IOException {
        expect('"');
        StringBuilder sb = new StringBuilder();
        while (true) {
            if (i >= s.length()) {
                throw fail("unterminated string");
            }
            char c = s.charAt(i++);
            if (c == '"') {
                return sb.toString();
            }
            if (c != '\\') {
                sb.append(c);
                continue;
            }
            if (i >= s.length()) {
                throw fail("unterminated escape");
            }
            char e = s.charAt(i++);
            switch (e) {
                case '"':  sb.append('"');  break;
                case '\\': sb.append('\\'); break;
                case '/':  sb.append('/');  break;
                case 'b':  sb.append('\b'); break;
                case 'f':  sb.append('\f'); break;
                case 'n':  sb.append('\n'); break;
                case 'r':  sb.append('\r'); break;
                case 't':  sb.append('\t'); break;
                case 'u':
                    if (i + 4 > s.length()) {
                        throw fail("truncated \\u escape");
                    }
                    sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                    i += 4;
                    break;
                default:
                    throw fail("bad escape '\\" + e + "'");
            }
        }
    }

    private Double number() throws IOException {
        int start = i;
        if (peek() == '-') {
            i++;
        }
        while (i < s.length() && isNum(s.charAt(i))) {
            i++;
        }
        if (i == start) {
            throw fail("expected a value");
        }
        try {
            return Double.valueOf(s.substring(start, i));
        } catch (NumberFormatException e) {
            throw fail("bad number '" + s.substring(start, i) + "'");
        }
    }

    private static boolean isNum(char c) {
        return (c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-';
    }

    private void literal(String want) throws IOException {
        if (!s.startsWith(want, i)) {
            throw fail("expected " + want);
        }
        i += want.length();
    }

    private void ws() {
        while (i < s.length()) {
            char c = s.charAt(i);
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                i++;
            } else {
                return;
            }
        }
    }

    private char peek() {
        return i < s.length() ? s.charAt(i) : '\0';
    }

    private char next() throws IOException {
        if (i >= s.length()) {
            throw fail("unexpected end of input");
        }
        return s.charAt(i++);
    }

    private void expect(char c) throws IOException {
        if (next() != c) {
            i--;
            throw fail("expected '" + c + "'");
        }
    }

    private IOException fail(String msg) {
        return new IOException("json: " + msg + " at offset " + i);
    }
}
