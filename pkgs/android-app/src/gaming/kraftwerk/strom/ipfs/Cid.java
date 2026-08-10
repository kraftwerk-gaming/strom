package gaming.kraftwerk.strom.ipfs;

import java.util.Arrays;

/**
 * A content identifier, restricted to what this repo actually pins:
 * sha2-256 digests under either the raw or dag-pb codec. CIDv0 ("Qm...",
 * base58btc, implicitly dag-pb) and CIDv1 ("b...", base32) both decode
 * here; anything else is rejected loudly rather than guessed at, because
 * a CID we cannot represent is a CID we cannot verify against.
 */
public final class Cid {
    public static final int CODEC_RAW = 0x55;
    public static final int CODEC_DAG_PB = 0x70;
    public static final int MH_SHA2_256 = 0x12;

    public final int version;
    public final int codec;
    /** The 32-byte sha2-256 digest. Not copied on the way out; do not mutate. */
    public final byte[] digest;

    public Cid(int version, int codec, byte[] digest) {
        if (digest.length != 32) {
            throw new IllegalArgumentException("expected a 32-byte digest, got " + digest.length);
        }
        this.version = version;
        this.codec = codec;
        this.digest = digest;
    }

    /** A decoded CID plus the offset just past it. */
    public static final class Parsed {
        public final Cid cid;
        public final int next;

        Parsed(Cid cid, int next) {
            this.cid = cid;
            this.next = next;
        }
    }

    /**
     * Parse a binary CID at {@code buf[off]}, as it appears in a CAR block
     * header or a dag-pb link.
     */
    public static Parsed parse(byte[] buf, int off) throws VerifyException {
        if (off + 2 <= buf.length && (buf[off] & 0xff) == 0x12 && (buf[off + 1] & 0xff) == 0x20) {
            // CIDv0: a bare sha2-256 multihash, no version or codec prefix.
            if (off + 34 > buf.length) {
                throw new VerifyException("truncated CIDv0");
            }
            return new Parsed(
                new Cid(0, CODEC_DAG_PB, Arrays.copyOfRange(buf, off + 2, off + 34)),
                off + 34);
        }

        Varint.Result v = Varint.from(buf, off);
        if (v.value != 1) {
            throw new VerifyException("unsupported CID version " + v.value);
        }
        Varint.Result c = Varint.from(buf, v.next);
        int codec = (int) c.value;
        if (codec != CODEC_RAW && codec != CODEC_DAG_PB) {
            throw new VerifyException("unsupported CID codec 0x" + Integer.toHexString(codec));
        }
        Varint.Result h = Varint.from(buf, c.next);
        if (h.value != MH_SHA2_256) {
            throw new VerifyException("unsupported multihash 0x" + Long.toHexString(h.value));
        }
        Varint.Result len = Varint.from(buf, h.next);
        if (len.value != 32) {
            throw new VerifyException("expected a 32-byte digest, got " + len.value);
        }
        if (len.next + 32 > buf.length) {
            throw new VerifyException("truncated CID digest");
        }
        return new Parsed(
            new Cid(1, codec, Arrays.copyOfRange(buf, len.next, len.next + 32)),
            len.next + 32);
    }

    /** Decode a textual CID: CIDv0 base58btc "Qm..." or CIDv1 base32 "b...". */
    public static Cid fromText(String s) throws VerifyException {
        if (s.startsWith("Qm") || s.startsWith("1")) {
            byte[] raw = Base58.decode(s);
            return parse(raw, 0).cid;
        }
        if (s.startsWith("b")) {
            byte[] raw = Base32.decode(s.substring(1));
            return parse(raw, 0).cid;
        }
        throw new VerifyException("unrecognised CID encoding: "
            + s.substring(0, Math.min(8, s.length())));
    }

    /** The binary form, as it appears inside a CAR block header. */
    public byte[] toBytes() {
        if (version == 0) {
            byte[] out = new byte[34];
            out[0] = 0x12;
            out[1] = 0x20;
            System.arraycopy(digest, 0, out, 2, 32);
            return out;
        }
        byte[] out = new byte[36];
        out[0] = 0x01;
        out[1] = (byte) codec;
        out[2] = 0x12;
        out[3] = 0x20;
        System.arraycopy(digest, 0, out, 4, 32);
        return out;
    }

    public String toText() {
        if (version == 0) {
            return Base58.encode(toBytes());
        }
        return "b" + Base32.encode(toBytes());
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof Cid)) {
            return false;
        }
        Cid other = (Cid) o;
        // Version is deliberately not compared: a CIDv0 and a CIDv1 dag-pb
        // over the same digest address the same block, and gateways
        // normalise between them (a v0 request can redirect to a v1 host).
        return codec == other.codec && Arrays.equals(digest, other.digest);
    }

    @Override
    public int hashCode() {
        return 31 * codec + Arrays.hashCode(digest);
    }

    @Override
    public String toString() {
        return toText();
    }
}
