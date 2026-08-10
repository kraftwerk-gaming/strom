package gaming.kraftwerk.strom.ipfs;

import java.io.IOException;
import java.io.InputStream;

/**
 * Unsigned LEB128, the length prefix used by both CAR framing and
 * protobuf. Values here are bounded well under 2^63 in practice (a CAR
 * frame length, a protobuf field length, a UnixFS file size), so a long
 * is enough and anything longer is treated as corruption rather than
 * silently truncated.
 */
public final class Varint {
    private Varint() {
    }

    /** A decoded value plus the offset just past it. */
    public static final class Result {
        public final long value;
        public final int next;

        Result(long value, int next) {
            this.value = value;
            this.next = next;
        }
    }

    /**
     * Read a varint from a stream.
     *
     * @return the value, or -1 at a clean end of stream (no bytes read).
     *         A stream that ends mid-varint is corruption, not an end.
     */
    public static long read(InputStream in) throws IOException {
        long value = 0;
        int shift = 0;
        boolean any = false;
        while (true) {
            int b = in.read();
            if (b < 0) {
                if (!any) {
                    return -1;
                }
                throw new VerifyException("stream ended mid-varint");
            }
            any = true;
            value |= ((long) (b & 0x7f)) << shift;
            if ((b & 0x80) == 0) {
                return value;
            }
            shift += 7;
            if (shift > 63) {
                throw new VerifyException("varint too long");
            }
        }
    }

    /** Read a varint out of a buffer at {@code off}. */
    public static Result from(byte[] buf, int off) throws VerifyException {
        long value = 0;
        int shift = 0;
        int i = off;
        while (true) {
            if (i >= buf.length) {
                throw new VerifyException("varint ran off the end of the buffer");
            }
            int b = buf[i++] & 0xff;
            value |= ((long) (b & 0x7f)) << shift;
            if ((b & 0x80) == 0) {
                return new Result(value, i);
            }
            shift += 7;
            if (shift > 63) {
                throw new VerifyException("varint too long");
            }
        }
    }
}
