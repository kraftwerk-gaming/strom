package gaming.kraftwerk.strom.ipfs;

/**
 * Just enough protobuf to read the two message shapes IPFS uses: dag-pb's
 * PBNode/PBLink and the UnixFS Data message nested inside it. Written by
 * hand rather than pulled in as a dependency because it is a few dozen
 * lines and the client otherwise has none.
 */
public final class Protobuf {
    public static final int WIRE_VARINT = 0;
    public static final int WIRE_LEN = 2;

    private Protobuf() {
    }

    /** Called for each field in a message. */
    public interface FieldSink {
        /**
         * @param field the field number
         * @param wire  the wire type
         * @param num   the value for a varint field
         * @param buf   the backing array for a length-delimited field
         * @param off   start of the payload within {@code buf}
         * @param len   length of the payload
         */
        void field(int field, int wire, long num, byte[] buf, int off, int len)
            throws VerifyException;
    }

    public static void walk(byte[] buf, int from, int to, FieldSink sink) throws VerifyException {
        int i = from;
        while (i < to) {
            Varint.Result key = Varint.from(buf, i);
            int field = (int) (key.value >>> 3);
            int wire = (int) (key.value & 7);
            i = key.next;
            switch (wire) {
                case WIRE_VARINT: {
                    Varint.Result v = Varint.from(buf, i);
                    sink.field(field, wire, v.value, buf, i, 0);
                    i = v.next;
                    break;
                }
                case WIRE_LEN: {
                    Varint.Result n = Varint.from(buf, i);
                    int len = (int) n.value;
                    if (len < 0 || n.next + len > to) {
                        throw new VerifyException("protobuf field runs past the message");
                    }
                    sink.field(field, wire, len, buf, n.next, len);
                    i = n.next + len;
                    break;
                }
                default:
                    throw new VerifyException("unsupported protobuf wire type " + wire);
            }
        }
        if (i != to) {
            throw new VerifyException("protobuf message overran its length");
        }
    }

    public static void walk(byte[] buf, FieldSink sink) throws VerifyException {
        walk(buf, 0, buf.length, sink);
    }
}
