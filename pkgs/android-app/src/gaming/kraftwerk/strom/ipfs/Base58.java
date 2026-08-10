package gaming.kraftwerk.strom.ipfs;

import java.math.BigInteger;

/** base58btc, for CIDv0 text. */
public final class Base58 {
    private static final String ALPHABET =
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    private static final BigInteger BASE = BigInteger.valueOf(58);

    private Base58() {
    }

    public static byte[] decode(String s) throws VerifyException {
        BigInteger n = BigInteger.ZERO;
        for (int i = 0; i < s.length(); i++) {
            int d = ALPHABET.indexOf(s.charAt(i));
            if (d < 0) {
                throw new VerifyException("bad base58 character '" + s.charAt(i) + "'");
            }
            n = n.multiply(BASE).add(BigInteger.valueOf(d));
        }
        byte[] body = n.toByteArray();
        // BigInteger prepends a zero byte when the top bit is set; drop it.
        int from = (body.length > 1 && body[0] == 0) ? 1 : 0;

        int pad = 0;
        while (pad < s.length() && s.charAt(pad) == '1') {
            pad++;
        }

        byte[] out = new byte[pad + body.length - from];
        System.arraycopy(body, from, out, pad, body.length - from);
        return out;
    }

    public static String encode(byte[] raw) {
        BigInteger n = new BigInteger(1, raw);
        StringBuilder sb = new StringBuilder();
        while (n.signum() > 0) {
            BigInteger[] qr = n.divideAndRemainder(BASE);
            sb.append(ALPHABET.charAt(qr[1].intValue()));
            n = qr[0];
        }
        for (int i = 0; i < raw.length && raw[i] == 0; i++) {
            sb.append('1');
        }
        return sb.reverse().toString();
    }
}
