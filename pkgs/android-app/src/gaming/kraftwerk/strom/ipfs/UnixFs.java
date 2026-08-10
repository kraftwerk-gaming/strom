package gaming.kraftwerk.strom.ipfs;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;

/**
 * Rebuilds a UnixFS file or directory tree out of a CAR stream, writing
 * blocks out as they arrive.
 *
 * <p>Trustless gateways answer with {@code order=dfs; dups=n}: a parent
 * always precedes its children and no block repeats. So the next block on
 * the wire is always the next block the walk expects, and nothing has to
 * be buffered - which is the only reason a multi-GB game tree is viable
 * on a phone. Every deviation from that order is treated as a
 * verification failure rather than papered over by buffering.
 */
public final class UnixFs {
    /** UnixFS Data.Type. */
    private static final int TYPE_RAW = 0;
    private static final int TYPE_DIR = 1;
    private static final int TYPE_FILE = 2;

    public static final class Stats {
        /** Blocks received on the wire. */
        public long blocks;
        public long bytesOut;
        public long files;
        /**
         * References served from an earlier copy of the same block. Nonzero
         * whenever the payload repeats content, which most ROMs do.
         */
        public long duplicates;
    }

    private UnixFs() {
    }

    /**
     * Walk a whole CAR, header included, writing the tree under
     * {@code dest}. {@code dest} is the file itself when the root is a
     * file, or the directory root when the root is a directory.
     */
    public static Stats extract(InputStream carStream, Cid root, File dest) throws IOException {
        Walker w = new Walker(root, dest);
        try {
            Car.stream(carStream, w);
            w.finish();
        } finally {
            w.abandon();
        }
        return w.stats;
    }

    /** As {@link #extract}, for a stream whose header the caller already read. */
    static Stats extractBlocks(InputStream carStream, Cid root, File dest) throws IOException {
        Walker w = new Walker(root, dest);
        try {
            Car.streamBlocks(carStream, w);
            w.finish();
        } finally {
            w.abandon();
        }
        return w.stats;
    }

    // ----------------------------------------------------------------
    // dag-pb
    // ----------------------------------------------------------------

    private static final class Link {
        final Cid cid;
        final String name;

        Link(Cid cid, String name) {
            this.cid = cid;
            this.name = name;
        }
    }

    /** PBNode { Data = 1 bytes, Links = 2 repeated PBLink }. */
    private static final class Node implements Protobuf.FieldSink {
        /** Offsets into the block itself; the payload is never copied out. */
        int dataOff = -1;
        int dataLen;
        final List<Link> links = new ArrayList<Link>();

        static Node decode(byte[] block) throws VerifyException {
            Node n = new Node();
            Protobuf.walk(block, n);
            return n;
        }

        @Override
        public void field(int field, int wire, long num, byte[] buf, int off, int len)
            throws VerifyException {
            if (wire != Protobuf.WIRE_LEN) {
                return;
            }
            if (field == 1) {
                dataOff = off;
                dataLen = len;
            } else if (field == 2) {
                LinkSink l = new LinkSink();
                Protobuf.walk(buf, off, off + len, l);
                if (l.cid == null) {
                    throw new VerifyException("dag-pb link without Hash");
                }
                links.add(new Link(l.cid, l.name));
            }
        }
    }

    /** PBLink { Hash = 1 bytes, Name = 2 string, Tsize = 3 uint64 }. */
    private static final class LinkSink implements Protobuf.FieldSink {
        Cid cid;
        String name = "";

        @Override
        public void field(int field, int wire, long num, byte[] buf, int off, int len)
            throws VerifyException {
            if (wire != Protobuf.WIRE_LEN) {
                return;
            }
            if (field == 1) {
                Cid.Parsed p = Cid.parse(buf, off);
                // The field must hold a CID and nothing else, or a link
                // could quietly borrow bytes from the field after it.
                if (p.next != off + len) {
                    throw new VerifyException("dag-pb link Hash is not exactly one CID");
                }
                cid = p.cid;
            } else if (field == 2) {
                name = new String(buf, off, len, StandardCharsets.UTF_8);
            }
        }
    }

    /** UnixFS Data { Type = 1, Data = 2, filesize = 3, blocksizes = 4 }. */
    private static final class Data implements Protobuf.FieldSink {
        int type = TYPE_FILE;
        int dataOff = -1;
        int dataLen;
        /** -1 when the node does not declare one. */
        long filesize = -1;

        static Data decode(byte[] buf, int off, int len) throws VerifyException {
            Data d = new Data();
            Protobuf.walk(buf, off, off + len, d);
            return d;
        }

        static Data directory() {
            Data d = new Data();
            d.type = TYPE_DIR;
            return d;
        }

        @Override
        public void field(int field, int wire, long num, byte[] buf, int off, int len) {
            if (field == 1 && wire == Protobuf.WIRE_VARINT) {
                type = (int) num;
            } else if (field == 2 && wire == Protobuf.WIRE_LEN) {
                dataOff = off;
                dataLen = len;
            } else if (field == 3 && wire == Protobuf.WIRE_VARINT) {
                filesize = num;
            }
        }
    }

    // ----------------------------------------------------------------
    // the walk
    // ----------------------------------------------------------------

    /** A block the walk expects next, and where its bytes belong. */
    private static final class Expect {
        final Cid cid;
        final String path;
        /**
         * True when this block is part of the file currently being
         * assembled, so its content appends rather than starting a file.
         */
        final boolean append;

        Expect(Cid cid, String path, boolean append) {
            this.cid = cid;
            this.path = path;
            this.append = append;
        }
    }

    private static final class Walker implements Car.BlockSink {
        final File dest;
        final Stats stats = new Stats();
        final ArrayDeque<Expect> expect = new ArrayDeque<Expect>();

        OutputStream sink;
        String sinkPath;
        long sinkWritten;
        long sinkSize = -1;
        /**
         * Blocks of the open file's subtree still outstanding. A counter
         * rather than a link count because a large file's tree is deeper
         * than one level: interior nodes replace themselves with their own
         * children here.
         */
        long pending;

        /**
         * Blocks kept in case the DAG references them again.
         *
         * <p>Bounded, because a payload is far larger than memory: this is
         * an LRU over CACHE_MAX bytes. Duplicates are near neighbours in
         * practice, since the runs of identical padding that create them
         * sit together in the file, so a modest window catches them. If one
         * is ever evicted before its second reference the walk fails
         * loudly, which is the right outcome -- silently writing the wrong
         * bytes is the thing this class exists to prevent.
         */
        static final int CACHE_MAX = 24 * 1024 * 1024;
        final java.util.LinkedHashMap<Cid, byte[]> seen =
            new java.util.LinkedHashMap<Cid, byte[]>(64, 0.75f, true);
        long cached;

        private void remember(Cid cid, byte[] data) {
            if (data.length > CACHE_MAX) {
                return;
            }
            if (seen.put(cid, data) == null) {
                cached += data.length;
            }
            java.util.Iterator<java.util.Map.Entry<Cid, byte[]>> it = seen.entrySet().iterator();
            while (cached > CACHE_MAX && it.hasNext()) {
                cached -= it.next().getValue().length;
                it.remove();
            }
        }

        Walker(Cid root, File dest) {
            this.dest = dest;
            expect.addLast(new Expect(root, "", false));
        }

        @Override
        public void block(Cid cid, byte[] data) throws IOException {
            stats.blocks++;
            // A block the walk already expects may have been satisfied by an
            // earlier copy of itself; clear those before matching this one.
            replay();

            Expect e = expect.pollFirst();
            if (e == null) {
                throw new VerifyException("CAR contains more blocks than the DAG references");
            }
            if (!e.cid.equals(cid)) {
                throw new VerifyException("out-of-order block: expected " + e.cid + ", got " + cid);
            }
            remember(cid, data);
            place(e, cid, data);
        }

        /**
         * Satisfy expectations for blocks that have already arrived.
         *
         * <p>A gateway serving {@code dups=n} transmits each distinct block
         * once, however many times the DAG points at it, and real payloads
         * point at the same block often: a ROM's padding chunks are byte
         * identical, so they share a CID. Every reference after the first
         * has to be served from what we kept, or the walk ends holding
         * expectations nothing will ever fill.
         */
        private void replay() throws IOException {
            while (!expect.isEmpty()) {
                byte[] cached = seen.get(expect.peekFirst().cid);
                if (cached == null) {
                    return;
                }
                Expect e = expect.pollFirst();
                stats.duplicates++;
                place(e, e.cid, cached);
            }
        }

        /** Write a block's content, wherever the bytes came from. */
        private void place(Expect e, Cid cid, byte[] data) throws IOException {
            if (e.append && sink == null) {
                throw new VerifyException("no open file for " + cid);
            }
            if (!e.append && sink != null) {
                throw new VerifyException("block for " + e.path + " arrived inside " + sinkPath);
            }
            if (cid.codec == Cid.CODEC_RAW) {
                // A raw leaf is file content verbatim; this repo pins with
                // --raw-leaves, so most of a payload arrives this way.
                if (e.append) {
                    append(data, 0, data.length);
                    consumed(0);
                } else {
                    writeWhole(e.path, data, 0, data.length);
                }
                return;
            }
            if (cid.codec != Cid.CODEC_DAG_PB) {
                throw new VerifyException("unexpected codec 0x" + Integer.toHexString(cid.codec));
            }

            Node node = Node.decode(data);
            Data u = node.dataLen > 0
                ? Data.decode(data, node.dataOff, node.dataLen)
                : Data.directory();

            if (u.type == TYPE_DIR) {
                if (e.append) {
                    throw new VerifyException("directory block inside file " + sinkPath);
                }
                mkdirs(e.path.isEmpty() ? dest : new File(dest, e.path));
                pushChildren(node, e.path, false);
                return;
            }
            if (u.type != TYPE_FILE && u.type != TYPE_RAW) {
                throw new VerifyException("unsupported UnixFS type " + u.type);
            }

            if (e.append) {
                // An interior node of the open file, or a leaf that carries
                // its bytes inline instead of as a raw block.
                if (u.dataLen > 0) {
                    append(data, u.dataOff, u.dataLen);
                }
                consumed(node.links.size());
                pushChildren(node, e.path, true);
                return;
            }
            if (node.links.isEmpty()) {
                writeWhole(e.path, data, u.dataOff, u.dataLen);
                return;
            }
            open(e.path, u.filesize);
            // A chunked file may still carry a prefix of its own content.
            if (u.dataLen > 0) {
                append(data, u.dataOff, u.dataLen);
            }
            pending = node.links.size();
            pushChildren(node, e.path, true);
        }

        /** Push links so the first one is the very next block expected. */
        private void pushChildren(Node node, String path, boolean append) throws VerifyException {
            for (int i = node.links.size() - 1; i >= 0; i--) {
                Link ln = node.links.get(i);
                expect.addFirst(new Expect(ln.cid, append ? path : child(path, ln.name), append));
            }
        }

        /** Account for one block of the open file, plus the children it brings. */
        private void consumed(int children) throws IOException {
            pending += children - 1;
            if (pending > 0) {
                return;
            }
            OutputStream out = sink;
            sink = null;
            out.close();
            if (sinkSize >= 0 && sinkWritten != sinkSize) {
                throw new VerifyException("file " + sinkPath + " came to " + sinkWritten
                    + " bytes, its UnixFS header declares " + sinkSize);
            }
        }

        private void append(byte[] buf, int off, int len) throws IOException {
            sink.write(buf, off, len);
            sinkWritten += len;
            stats.bytesOut += len;
        }

        private void open(String path, long filesize) throws IOException {
            File f = path.isEmpty() ? dest : new File(dest, path);
            File parent = f.getParentFile();
            if (parent != null) {
                mkdirs(parent);
            }
            sink = new FileOutputStream(f);
            sinkPath = path;
            sinkWritten = 0;
            sinkSize = filesize;
            stats.files++;
        }

        /** A file that fits in one block: opened, written and closed here. */
        private void writeWhole(String path, byte[] buf, int off, int len) throws IOException {
            open(path, -1);
            try {
                if (len > 0) {
                    append(buf, off, len);
                }
            } finally {
                OutputStream out = sink;
                sink = null;
                out.close();
            }
        }

        private void finish() throws IOException {
            // The tail of a payload is often its most repetitive part, so
            // the last references frequently resolve to blocks already seen
            // rather than to anything still on the wire.
            replay();

            boolean midFile = sink != null;
            if (midFile) {
                OutputStream out = sink;
                sink = null;
                out.close();
            }
            if (!expect.isEmpty()) {
                throw new VerifyException("CAR ended with " + expect.size()
                    + " block(s) unaccounted for; " + expect.peekFirst().cid
                    + " was never sent and is not in the recent-block cache");
            }
            if (midFile) {
                throw new VerifyException("CAR ended mid-file");
            }
        }

        /** Release a half-written file when the walk is abandoned. */
        private void abandon() {
            OutputStream out = sink;
            sink = null;
            if (out == null) {
                return;
            }
            try {
                out.close();
            } catch (IOException ignored) {
                // The interesting failure is the one already propagating.
            }
        }
    }

    private static String child(String parent, String name) throws VerifyException {
        // Link names are single path components. A separator or a dotted
        // name would let a published DAG write outside the directory we
        // chose for it; a backslash is just an ordinary character here.
        if (name.isEmpty() || name.equals(".") || name.equals("..")
            || name.indexOf('/') >= 0 || name.indexOf('\0') >= 0) {
            throw new VerifyException("unsafe directory entry name: " + name);
        }
        return parent.isEmpty() ? name : parent + "/" + name;
    }

    private static void mkdirs(File dir) throws IOException {
        if (dir.isDirectory()) {
            return;
        }
        if (!dir.mkdirs() && !dir.isDirectory()) {
            throw new IOException("cannot create directory " + dir);
        }
    }
}
