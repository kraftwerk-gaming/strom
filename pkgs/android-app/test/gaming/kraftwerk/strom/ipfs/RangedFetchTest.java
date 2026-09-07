package gaming.kraftwerk.strom.ipfs;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.net.InetSocketAddress;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * A single-file payload is fetched by byte range, in pieces, and a piece
 * that finished is not fetched again -- after a cut stream, and after a
 * restart.
 *
 * <p>The fixture is a chunked UnixFS file two levels deep, as kubo lays
 * out anything over a few MB: a root naming two interior nodes, each
 * naming raw leaves. The gateway stands in for one that serves interior
 * blocks as scoped CARs and the file's bytes with Range support, and can
 * cut a range response short, serve a wrong byte, or ignore Range.
 */
public final class RangedFetchTest {
    private static int failures = 0;

    public static void main(String[] args) throws Exception {
        Ranged.setPieceBytesForTest(3 * Fixture.LEAF);
        try {
            fetchesAChunkedFileByRange();
            resumesAfterACutRange();
            resumesAfterARestart();
            rejectsALeafThatDoesNotHash();
            refusesAGatewayThatIgnoresRange();
            layoutRejectsADagPbLeaf();
        } finally {
            Ranged.setPieceBytesForTest(0);
        }

        if (failures > 0) {
            System.err.println(failures + " test(s) failed");
            System.exit(1);
        }
        System.out.println("all ranged fetch tests passed");
    }

    // ---- tests -----------------------------------------------------------

    private static void fetchesAChunkedFileByRange() throws Exception {
        Fixture f = Fixture.build(25);
        Gateway gw = new Gateway(f);
        try {
            File out = CarVerifyTest.tmp("ranged");
            UnixFs.Stats st = Fetcher.fetchFile(f.root.toText(), out, null);
            check("file is byte-identical", Arrays.equals(f.bytes, Files.readAllBytes(out.toPath())));
            check("stats count the leaves", st.blocks == 25 && st.bytesOut == f.bytes.length);
            check("state file is gone", !Ranged.stateFile(out).exists());
            check("interior nodes fetched as blocks: root + 2", gw.blockHits == 3);
            // 25 leaves in pieces of 3: nine ranges.
            check("nine range requests, one per piece", gw.ranges.size() == 9);
        } finally {
            gw.stop();
        }
    }

    private static void resumesAfterACutRange() throws Exception {
        Fixture f = Fixture.build(25);
        Gateway gw = new Gateway(f);
        gw.cutFirstRangeAt = 4 * 3 * Fixture.LEAF;   // the fifth piece
        try {
            File out = CarVerifyTest.tmp("cut");
            Fetcher.fetchFile(f.root.toText(), out, null);
            check("file is byte-identical after a cut", Arrays.equals(f.bytes, Files.readAllBytes(out.toPath())));
            check("the cut piece was asked for twice", gw.count(gw.cutFirstRangeAt) == 2);
            check("the others once", gw.count(0) == 1 && gw.count(8 * 3 * Fixture.LEAF) == 1);
        } finally {
            gw.stop();
        }
    }

    private static void resumesAfterARestart() throws Exception {
        Fixture f = Fixture.build(25);
        Gateway gw = new Gateway(f);
        try {
            File out = CarVerifyTest.tmp("restart");
            // What a killed app leaves: the file at full length holding the
            // first four pieces, and a state file saying so.
            RandomAccessFile raf = new RandomAccessFile(out, "rw");
            raf.setLength(f.bytes.length);
            raf.write(f.bytes, 0, 4 * 3 * Fixture.LEAF);
            raf.close();
            Files.write(Ranged.stateFile(out).toPath(),
                (f.root.toText() + "\n111100000\n").getBytes("UTF-8"));
            final long[] seen = new long[1];
            Fetcher.fetchFile(f.root.toText(), out, new Fetcher.Progress() {
                @Override
                public void bytes(long n) {
                    if (seen[0] == 0) {
                        seen[0] = n;
                    }
                }

                @Override
                public void trying(String gateway) {
                }

                @Override
                public void gatewayFailed(String gateway, IOException e) {
                }
            });
            check("file is byte-identical after a restart", Arrays.equals(f.bytes, Files.readAllBytes(out.toPath())));
            check("finished pieces were not asked for again", gw.ranges.size() == 5
                && gw.count(0) == 0 && gw.count(3 * 3 * Fixture.LEAF) == 0);
            check("progress starts from what was verified", seen[0] == 4 * 3 * Fixture.LEAF);
            check("state file is gone", !Ranged.stateFile(out).exists());
        } finally {
            gw.stop();
        }
    }

    private static void rejectsALeafThatDoesNotHash() throws Exception {
        Fixture f = Fixture.build(25);
        Gateway gw = new Gateway(f);
        gw.flipByteAt = 7 * Fixture.LEAF + 5;
        try {
            File out = CarVerifyTest.tmp("tampered");
            try {
                Fetcher.fetchFile(f.root.toText(), out, null);
                check("a tampered leaf is rejected", false);
            } catch (VerifyException e) {
                check("a tampered leaf is rejected: " + e.getMessage(), true);
            }
            byte[] got = Files.readAllBytes(out.toPath());
            check("the bad leaf was never written",
                got[7 * Fixture.LEAF + 5] == 0 && got[0] == f.bytes[0]);
            check("state survives for a retry", Ranged.stateFile(out).isFile());
        } finally {
            gw.stop();
        }
    }

    private static void refusesAGatewayThatIgnoresRange() throws Exception {
        Fixture f = Fixture.build(4);
        Gateway gw = new Gateway(f);
        gw.ignoreRange = true;
        try {
            File out = CarVerifyTest.tmp("norange");
            try {
                Fetcher.fetchFile(f.root.toText(), out, null);
                check("a 200 to a Range request is a failure", false);
            } catch (IOException e) {
                check("a 200 to a Range request is a failure: " + e.getMessage(),
                    e.getMessage().contains("HTTP 200"));
            }
        } finally {
            gw.stop();
        }
    }

    private static void layoutRejectsADagPbLeaf() throws Exception {
        // A file whose leaf is a dag-pb node (no --raw-leaves): its bytes
        // cannot be checked against the leaf CID without rebuilding the
        // wrapper, so the layout refuses rather than the download guessing.
        // Whether a child is such a leaf is only known once its block is
        // read, so the refusal comes from the layout walk, not the root.
        byte[] content = new byte[100];
        java.io.ByteArrayOutputStream u = new java.io.ByteArrayOutputStream();
        u.write(0x08);
        u.write(2);                                          // Type = file
        u.write(0x12);
        u.write(content.length);                             // Data, inline
        u.write(content);
        u.write(0x18);
        u.write(content.length);                             // filesize
        java.io.ByteArrayOutputStream node = new java.io.ByteArrayOutputStream();
        node.write(0x0a);
        node.write(u.size());
        node.write(u.toByteArray());
        byte[] innerNode = node.toByteArray();
        Cid inner = CarVerifyTest.dagCid(innerNode);
        byte[] rootNode = CarVerifyTest.fileNode(new Cid[] { inner }, new int[] { 100 });
        Fixture f = new Fixture();
        f.bytes = content;
        f.root = CarVerifyTest.dagCid(rootNode);
        f.cars.put(f.root.toText(), CarVerifyTest.car(f.root,
            new CarVerifyTest.Block[] { new CarVerifyTest.Block(f.root, rootNode) }));
        f.cars.put(inner.toText(), CarVerifyTest.car(inner,
            new CarVerifyTest.Block[] { new CarVerifyTest.Block(inner, innerNode) }));
        Gateway gw = new Gateway(f);
        try {
            Fetcher.fetchFile(f.root.toText(), CarVerifyTest.tmp("dagpb"), null);
            check("a dag-pb leaf is refused", false);
        } catch (VerifyException e) {
            check("a dag-pb leaf is refused: " + e.getMessage(), true);
        } finally {
            gw.stop();
        }
    }

    // ---- fixtures --------------------------------------------------------

    /** A chunked file: root -> two interior nodes -> raw leaves of LEAF bytes. */
    private static final class Fixture {
        static final int LEAF = 4096;
        byte[] bytes;
        Cid root;
        /** cid text -> block-scoped CAR, for every interior node. */
        final Map<String, byte[]> cars = new HashMap<String, byte[]>();

        static Fixture build(int leaves) throws Exception {
            Fixture f = new Fixture();
            f.bytes = new byte[leaves * LEAF];
            for (int i = 0; i < f.bytes.length; i++) {
                f.bytes[i] = (byte) (i * 31 + (i >> 12));
            }
            List<Cid> leafCids = new ArrayList<Cid>();
            for (int i = 0; i < leaves; i++) {
                leafCids.add(CarVerifyTest.rawCid(Arrays.copyOfRange(f.bytes, i * LEAF, (i + 1) * LEAF)));
            }
            int split = (leaves + 1) / 2;
            Cid[] interior = new Cid[2];
            int[] interiorSizes = new int[2];
            for (int half = 0; half < 2; half++) {
                int from = half == 0 ? 0 : split;
                int to = half == 0 ? split : leaves;
                Cid[] cids = leafCids.subList(from, to).toArray(new Cid[0]);
                int[] sizes = new int[cids.length];
                Arrays.fill(sizes, LEAF);
                byte[] node = CarVerifyTest.fileNode(cids, sizes);
                interior[half] = CarVerifyTest.dagCid(node);
                interiorSizes[half] = cids.length * LEAF;
                f.cars.put(interior[half].toText(), CarVerifyTest.car(interior[half],
                    new CarVerifyTest.Block[] { new CarVerifyTest.Block(interior[half], node) }));
            }
            byte[] rootNode = CarVerifyTest.fileNode(interior, interiorSizes);
            f.root = CarVerifyTest.dagCid(rootNode);
            f.cars.put(f.root.toText(), CarVerifyTest.car(f.root,
                new CarVerifyTest.Block[] { new CarVerifyTest.Block(f.root, rootNode) }));
            return f;
        }
    }

    /** A gateway serving interior blocks as CARs and the file by Range. */
    private static final class Gateway {
        final HttpServer server;
        int blockHits;
        /** Offsets of every Range request, in arrival order. */
        final List<Long> ranges = new ArrayList<Long>();
        long cutFirstRangeAt = -1;
        int flipByteAt = -1;
        boolean ignoreRange;
        private boolean cutDone;

        Gateway(final Fixture f) throws IOException {
            server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/ipfs/", new HttpHandler() {
                @Override
                public void handle(HttpExchange x) throws IOException {
                    String path = x.getRequestURI().getPath().substring("/ipfs/".length());
                    String query = x.getRequestURI().getQuery();
                    if (query != null && query.contains("format=car")) {
                        byte[] car = f.cars.get(path);
                        if (car == null) {
                            x.sendResponseHeaders(404, -1);
                            x.close();
                            return;
                        }
                        synchronized (Gateway.this) {
                            blockHits++;
                        }
                        x.getResponseHeaders().add("Content-Type", "application/vnd.ipld.car");
                        x.sendResponseHeaders(200, car.length);
                        OutputStream o = x.getResponseBody();
                        o.write(car);
                        o.close();
                        return;
                    }
                    if (!path.equals(f.root.toText())) {
                        x.sendResponseHeaders(404, -1);
                        x.close();
                        return;
                    }
                    String range = x.getRequestHeaders().getFirst("Range");
                    if (range == null || ignoreRange) {
                        x.sendResponseHeaders(200, f.bytes.length);
                        OutputStream o = x.getResponseBody();
                        o.write(f.bytes);
                        o.close();
                        return;
                    }
                    String[] ends = range.substring("bytes=".length()).split("-");
                    long from = Long.parseLong(ends[0]);
                    long to = Long.parseLong(ends[1]);
                    boolean cut;
                    synchronized (Gateway.this) {
                        ranges.add(from);
                        cut = from == cutFirstRangeAt && !cutDone;
                        if (cut) {
                            cutDone = true;
                        }
                    }
                    byte[] body = Arrays.copyOfRange(f.bytes, (int) from, (int) to + 1);
                    if (flipByteAt >= from && flipByteAt <= to) {
                        body[(int) (flipByteAt - from)] ^= 0x01;
                    }
                    x.getResponseHeaders().add("Content-Range",
                        "bytes " + from + "-" + to + "/" + f.bytes.length);
                    x.sendResponseHeaders(206, cut ? body.length / 2 : body.length);
                    OutputStream o = x.getResponseBody();
                    o.write(body, 0, cut ? body.length / 2 : body.length);
                    o.close();
                }
            });
            server.start();
            Fetcher.setPrivateGateway("http://127.0.0.1:" + server.getAddress().getPort());
            Fetcher.setPublicGatewaysForTest(new String[0]);
        }

        synchronized int count(long offset) {
            int n = 0;
            for (int i = 0; i < ranges.size(); i++) {
                if (ranges.get(i) == offset) {
                    n++;
                }
            }
            return n;
        }

        void stop() {
            server.stop(0);
            Fetcher.setPrivateGateway("");
            Fetcher.setPublicGatewaysForTest(null);
        }
    }

    private static void check(String what, boolean ok) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) {
            failures++;
        }
    }
}
