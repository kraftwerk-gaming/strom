package gaming.kraftwerk.strom.ipfs;

/**
 * RFC 4648 base32, lowercase and unpadded, which is the multibase 'b'
 * encoding used for CIDv1 text.
 */
public final class Base32 {
    private static final String ALPHABET = "abcdefghijklmnopqrstuvwxyz234567";

    private Base32() {
    }

    public static byte[] decode(String s) throws VerifyException {
        int bits = 0;
        int acc = 0;
        int outLen = s.length() * 5 / 8;
        byte[] out = new byte[outLen];
        int o = 0;
        for (int i = 0; i < s.length(); i++) {
            char c = Character.toLowerCase(s.charAt(i));
            if (c == '=') {
                break;
            }
            int d = ALPHABET.indexOf(c);
            if (d < 0) {
                throw new VerifyException("bad base32 character '" + c + "'");
            }
            acc = (acc << 5) | d;
            bits += 5;
            if (bits >= 8) {
                bits -= 8;
                if (o >= out.length) {
                    throw new VerifyException("base32 overran its decoded length");
                }
                out[o++] = (byte) ((acc >> bits) & 0xff);
            }
        }
        if (o != out.length) {
            byte[] trimmed = new byte[o];
            System.arraycopy(out, 0, trimmed, 0, o);
            return trimmed;
        }
        return out;
    }

    public static String encode(byte[] raw) {
        StringBuilder sb = new StringBuilder();
        int bits = 0;
        int acc = 0;
        for (byte b : raw) {
            acc = (acc << 8) | (b & 0xff);
            bits += 8;
            while (bits >= 5) {
                bits -= 5;
                sb.append(ALPHABET.charAt((acc >> bits) & 0x1f));
            }
        }
        if (bits > 0) {
            sb.append(ALPHABET.charAt((acc << (5 - bits)) & 0x1f));
        }
        return sb.toString();
    }
}
