package gaming.kraftwerk.strom.ipfs;

import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.List;

/**
 * CARv1 framing: a varint-prefixed dag-cbor header, then one
 * varint-prefixed frame per block, each frame being a binary CID followed
 * by the block bytes.
 *
 * <p>Every block is hashed and compared against the CID that framed it
 * before it reaches the sink. That single check is what makes an
 * untrusted gateway safe to download from: the CID comes from the repo,
 * the bytes come from a stranger, and a stranger who alters a byte is
 * caught here.
 */
public final class Car {
    /**
     * Frame and header sizes are attacker-controlled varints, so they are
     * bounded before anything is allocated. IPFS chunks at 256 KiB and
     * refuses blocks over 2 MiB; a CAR header holds a handful of CIDs.
     */
    private static final int MAX_BLOCK = 8 << 20;
    private static final int MAX_HEADER = 64 << 10;
    /** Longest binary CID we accept: version, codec, hash code, length, digest. */
    private static final int MAX_CID = 40;

    /** CBOR major types, as used by the dag-cbor header. */
    private static final int CBOR_UINT = 0;
    private static final int CBOR_BYTES = 2;
    private static final int CBOR_TEXT = 3;
    private static final int CBOR_ARRAY = 4;
    private static final int CBOR_MAP = 5;
    private static final int CBOR_TAG = 6;
    /** The multibase-prefixed CID tag, the only tag dag-cbor defines. */
    private static final int TAG_CID = 42;

    public interface BlockSink {
        void block(Cid cid, byte[] data) throws IOException;
    }

    private Car() {
    }

    /** Read the header and return its roots, consuming nothing further. */
    public static List<Cid> readHeader(InputStream in) throws IOException {
        return roots(headerPayload(in));
    }

    /** Read a whole CARv1: the header, then every verified block. */
    public static void stream(InputStream in, BlockSink sink) throws IOException {
        headerPayload(in);
        streamBlocks(in, sink);
    }

    /**
     * The block frames alone, for a stream whose header {@link #readHeader}
     * has already consumed. Splitting the two lets a caller check the roots
     * against the CID it asked for before a single byte is written out.
     */
    static void streamBlocks(InputStream in, BlockSink sink) throws IOException {
        MessageDigest sha = sha256();
        while (true) {
            long len = Varint.read(in);
            if (len < 0) {
                return;
            }
            if (len < 1 || len > MAX_BLOCK) {
                throw new VerifyException("implausible CAR frame length " + len);
            }
            int frame = (int) len;

            // Read only as much as a CID can occupy, so the payload can be
            // read straight into its own array instead of being copied out
            // of a whole-frame buffer. Multi-GB trees make that copy real.
            int headLen = Math.min(frame, MAX_CID);
            byte[] head = new byte[headLen];
            readFully(in, head, 0, headLen);
            Cid.Parsed parsed = Cid.parse(head, 0);
            int cidLen = parsed.next;
            int dataLen = frame - cidLen;
            if (dataLen < 0) {
                throw new VerifyException("CAR frame shorter than the CID it carries");
            }
            byte[] data = new byte[dataLen];
            int carried = headLen - cidLen;
            System.arraycopy(head, cidLen, data, 0, carried);
            readFully(in, data, carried, dataLen - carried);

            sha.update(data);
            if (!MessageDigest.isEqual(sha.digest(), parsed.cid.digest)) {
                throw new VerifyException("block does not match its CID: " + parsed.cid);
            }
            sink.block(parsed.cid, data);
        }
    }

    private static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is missing from this JVM", e);
        }
    }

    private static byte[] headerPayload(InputStream in) throws IOException {
        long len = Varint.read(in);
        if (len < 0) {
            throw new VerifyException("empty CAR");
        }
        if (len < 1 || len > MAX_HEADER) {
            throw new VerifyException("implausible CAR header length " + len);
        }
        byte[] payload = new byte[(int) len];
        readFully(in, payload, 0, payload.length);
        return payload;
    }

    private static void readFully(InputStream in, byte[] buf, int off, int len)
        throws IOException {
        int done = 0;
        while (done < len) {
            int n = in.read(buf, off + done, len - done);
            if (n < 0) {
                throw new VerifyException("truncated CAR frame");
            }
            done += n;
        }
    }

    // ----------------------------------------------------------------
    // dag-cbor header
    //
    // The header is always {"version": 1, "roots": [CID, ...]}, but the
    // key order is not something to rely on, so the map is walked and
    // anything unrecognised skipped. This is not a general CBOR decoder
    // and does not want to be.
    // ----------------------------------------------------------------

    private static final class Cur {
        final byte[] b;
        int i;
        int major;

        Cur(byte[] b) {
            this.b = b;
        }
    }

    private static List<Cid> roots(byte[] payload) throws VerifyException {
        Cur c = new Cur(payload);
        long pairs = head(c);
        if (c.major != CBOR_MAP) {
            throw new VerifyException("CAR header is not a CBOR map");
        }
        List<Cid> found = null;
        for (long k = 0; k < pairs; k++) {
            String key = text(c);
            if ("roots".equals(key)) {
                found = rootArray(c);
            } else if ("version".equals(key)) {
                long version = head(c);
                if (c.major != CBOR_UINT || version != 1) {
                    throw new VerifyException("unsupported CAR version " + version);
                }
            } else {
                skip(c);
            }
        }
        if (found == null) {
            throw new VerifyException("CAR header has no roots");
        }
        return found;
    }

    private static List<Cid> rootArray(Cur c) throws VerifyException {
        long n = head(c);
        if (c.major != CBOR_ARRAY) {
            throw new VerifyException("CAR header roots is not an array");
        }
        if (n < 0 || n > 1024) {
            throw new VerifyException("implausible root count " + n);
        }
        List<Cid> out = new ArrayList<Cid>((int) n);
        for (long k = 0; k < n; k++) {
            long tag = head(c);
            if (c.major != CBOR_TAG || tag != TAG_CID) {
                throw new VerifyException("CAR header root is not a CID tag");
            }
            long len = head(c);
            if (c.major != CBOR_BYTES) {
                throw new VerifyException("CAR header root is not a byte string");
            }
            int off = c.i;
            int end = bound(c, len);
            // dag-cbor prefixes the binary CID with the identity multibase.
            if (end > off && c.b[off] == 0) {
                off++;
            }
            Cid.Parsed p = Cid.parse(c.b, off);
            if (p.next != end) {
                throw new VerifyException("trailing bytes after a CAR header root");
            }
            out.add(p.cid);
            c.i = end;
        }
        return out;
    }

    private static String text(Cur c) throws VerifyException {
        long len = head(c);
        if (c.major != CBOR_TEXT) {
            throw new VerifyException("CAR header key is not a string");
        }
        int off = c.i;
        int end = bound(c, len);
        c.i = end;
        StringBuilder sb = new StringBuilder(end - off);
        for (int i = off; i < end; i++) {
            sb.append((char) (c.b[i] & 0xff));
        }
        return sb.toString();
    }

    private static void skip(Cur c) throws VerifyException {
        long n = head(c);
        switch (c.major) {
            case CBOR_BYTES:
            case CBOR_TEXT:
                c.i = bound(c, n);
                return;
            case CBOR_ARRAY:
                for (long k = 0; k < n; k++) {
                    skip(c);
                }
                return;
            case CBOR_MAP:
                for (long k = 0; k < 2 * n; k++) {
                    skip(c);
                }
                return;
            case CBOR_TAG:
                skip(c);
                return;
            default:
                // Integers and simple values are fully consumed by head().
                return;
        }
    }

    /** Consume one CBOR item head, leaving its major type in {@code c.major}. */
    private static long head(Cur c) throws VerifyException {
        int b = u8(c);
        c.major = b >>> 5;
        int info = b & 0x1f;
        if (info < 24) {
            return info;
        }
        switch (info) {
            case 24:
                return u8(c);
            case 25:
                return (u8(c) << 8) | u8(c);
            case 26:
                return ((long) u8(c) << 24) | (u8(c) << 16) | (u8(c) << 8) | u8(c);
            case 27: {
                long v = 0;
                for (int k = 0; k < 8; k++) {
                    v = (v << 8) | u8(c);
                }
                if (v < 0) {
                    throw new VerifyException("CAR header integer out of range");
                }
                return v;
            }
            default:
                throw new VerifyException("indefinite-length CBOR in a CAR header");
        }
    }

    private static int u8(Cur c) throws VerifyException {
        if (c.i >= c.b.length) {
            throw new VerifyException("truncated CAR header");
        }
        return c.b[c.i++] & 0xff;
    }

    /** The end offset of a {@code len}-byte payload starting at the cursor. */
    private static int bound(Cur c, long len) throws VerifyException {
        if (len < 0 || len > c.b.length - c.i) {
            throw new VerifyException("CAR header field runs past the header");
        }
        return c.i + (int) len;
    }
}
