package gaming.kraftwerk.strom.ipfs;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;

/**
 * A directory payload is fetched one top-level entry at a time, and an
 * entry that finished is not fetched again.
 *
 * <p>A CAR is generated on the fly, so a gateway offers no byte-range
 * resume; a 3.6 GB tree in one HTTP response did not survive the
 * connection (measured: EOFException mid-stream, the whole download
 * gone, every retry from zero). These tests stand in a gateway that
 * serves scoped CARs -- dag-scope=block for the root, dag-scope=all per
 * entry -- and cuts one entry's stream
 * short on its first request, which is the failure that has to cost one
 * entry rather than the tree.
 */
public final class FetchResumeTest {
    private static int failures = 0;

    public static void main(String[] args) throws Exception {
        fetchesADirectoryEntryByEntry();
        resumesAfterACutStreamWithoutRefetchingFinishedEntries();
        aFilePayloadIsOneStream();
        resumesInsideANestedDirectory();

        if (failures > 0) {
            System.err.println(failures + " test(s) failed");
            System.exit(1);
        }
        System.out.println("all fetch resume tests passed");
    }

    // ---- tests -----------------------------------------------------------

    private static void fetchesADirectoryEntryByEntry() throws Exception {
        Tree t = Tree.twoFiles();
        Gateway gw = new Gateway(t);
        try {
            File out = CarVerifyTest.tmp("entrywise");
            UnixFs.Stats st = Fetcher.fetchAndExtract(t.root.toText(), out, null);

            check("both entries land", st.files == 2);
            check("entry a is right",
                java.util.Arrays.equals(t.a, Files.readAllBytes(new File(out, "a.bin").toPath())));
            check("entry b is right",
                java.util.Arrays.equals(t.b, Files.readAllBytes(new File(out, "b.bin").toPath())));
            check("the root was asked for once, as a block", gw.hits.get("root") == 1);
            // Once to see whether it is a directory, once for its bytes.
            check("each file was probed as a block, then fetched as a subtree",
                gw.hits.get("a") == 2 && gw.hits.get("b") == 2);
            check("no done markers are left behind",
                !new File(out.getAbsolutePath() + ".done").exists());
        } finally {
            gw.stop();
        }
    }

    private static void resumesAfterACutStreamWithoutRefetchingFinishedEntries() throws Exception {
        Tree t = Tree.twoFiles();
        Gateway gw = new Gateway(t);
        gw.cutFirstRequestFor = "b";
        try {
            File out = CarVerifyTest.tmp("resume");
            boolean failed = false;
            try {
                Fetcher.fetchAndExtract(t.root.toText(), out, null);
            } catch (IOException e) {
                failed = true;
            }
            check("a cut stream fails the fetch", failed);
            check("the entry that finished is on disk",
                java.util.Arrays.equals(t.a, Files.readAllBytes(new File(out, "a.bin").toPath())));
            check("the entry that was cut is not",
                !new File(out, "b.bin").exists());
            check("its done marker records the finished entry only",
                new File(out.getAbsolutePath() + ".done/a.bin").isFile()
                    && !new File(out.getAbsolutePath() + ".done/b.bin").exists());

            gw.hits.clear();
            UnixFs.Stats st = Fetcher.fetchAndExtract(t.root.toText(), out, null);
            check("the second run completes", st.files == 1);
            check("the finished entry was not asked for again", gw.hits.get("a") == null);
            check("the cut entry was probed and fetched", gw.hits.get("b") == 2);
            check("both entries are right now",
                java.util.Arrays.equals(t.a, Files.readAllBytes(new File(out, "a.bin").toPath()))
                    && java.util.Arrays.equals(t.b,
                        Files.readAllBytes(new File(out, "b.bin").toPath())));
            check("the done markers are gone once the tree is whole",
                !new File(out.getAbsolutePath() + ".done").exists());
        } finally {
            gw.stop();
        }
    }

    private static void aFilePayloadIsOneStream() throws Exception {
        byte[] content = "a rom".getBytes("UTF-8");
        Cid cid = CarVerifyTest.rawCid(content);
        Tree t = new Tree();
        t.root = cid;
        // A raw root is asked for twice: once as a block, to see whether it
        // is a directory, then as the one-stream file it turns out to be.
        byte[] car = CarVerifyTest.car(cid,
            new CarVerifyTest.Block[] { new CarVerifyTest.Block(cid, content) });
        t.blocks.put("root", car);
        t.blocks.put(cid.toText(), car);
        t.names.put(cid.toText(), "rom");
        Gateway gw = new Gateway(t);
        try {
            File out = CarVerifyTest.tmp("rom");
            UnixFs.Stats st = Fetcher.fetchAndExtract(cid.toText(), out, null);
            check("a raw root is written as the file itself",
                java.util.Arrays.equals(content, Files.readAllBytes(out.toPath())));
            check("one block", st.blocks == 1);
        } finally {
            gw.stop();
        }
    }

    /**
     * The unit is the file, not the top-level entry: FF8's 57 entries
     * include one directory holding 3 GB, and a per-entry fetch cut on it
     * exactly as the whole tree had.
     */
    private static void resumesInsideANestedDirectory() throws Exception {
        Tree t = Tree.nested();
        Gateway gw = new Gateway(t);
        gw.cutFirstRequestFor = "inner-b";
        try {
            File out = CarVerifyTest.tmp("nested");
            boolean failed = false;
            try {
                Fetcher.fetchAndExtract(t.root.toText(), out, null);
            } catch (IOException e) {
                failed = true;
            }
            check("a cut inside the directory fails the fetch", failed);
            check("the sibling that finished inside it is on disk",
                new File(out, "Data/a.bin").isFile());
            check("its marker sits under the directory's marker",
                new File(out.getAbsolutePath() + ".done/Data/a.bin").isFile());

            gw.hits.clear();
            UnixFs.Stats st = Fetcher.fetchAndExtract(t.root.toText(), out, null);
            check("the second run fetches only the cut file", st.files == 1
                && gw.hits.get("inner-a") == null && gw.hits.get("inner-b") == 2);
            check("the nested tree is whole",
                java.util.Arrays.equals(t.a, Files.readAllBytes(new File(out, "Data/a.bin").toPath()))
                    && java.util.Arrays.equals(t.b,
                        Files.readAllBytes(new File(out, "Data/b.bin").toPath())));
            check("the markers are gone", !new File(out.getAbsolutePath() + ".done").exists());
        } finally {
            gw.stop();
        }
    }

    // ---- fixtures --------------------------------------------------------

    /** A root directory with two raw-leaf files, each CAR precomputed. */
    private static final class Tree {
        Cid root;
        byte[] a;
        byte[] b;
        Cid ca;
        Cid cb;
        /** "root" -> root-only CAR; entry cid text -> that entry's CAR. */
        final Map<String, byte[]> blocks = new HashMap<String, byte[]>();
        final Map<String, String> names = new HashMap<String, String>();

        static Tree twoFiles() throws Exception {
            Tree t = new Tree();
            t.a = new byte[3000];
            t.b = new byte[5000];
            java.util.Arrays.fill(t.a, (byte) 'a');
            java.util.Arrays.fill(t.b, (byte) 'b');
            t.ca = CarVerifyTest.rawCid(t.a);
            t.cb = CarVerifyTest.rawCid(t.b);
            byte[] dir = CarVerifyTest.dirNode(new String[] { "a.bin", "b.bin" },
                new Cid[] { t.ca, t.cb }, new int[] { t.a.length, t.b.length });
            t.root = CarVerifyTest.dagCid(dir);
            t.blocks.put("root", CarVerifyTest.car(t.root,
                new CarVerifyTest.Block[] { new CarVerifyTest.Block(t.root, dir) }));
            t.blocks.put(t.ca.toText(), CarVerifyTest.car(t.ca,
                new CarVerifyTest.Block[] { new CarVerifyTest.Block(t.ca, t.a) }));
            t.blocks.put(t.cb.toText(), CarVerifyTest.car(t.cb,
                new CarVerifyTest.Block[] { new CarVerifyTest.Block(t.cb, t.b) }));
            t.names.put(t.ca.toText(), "a");
            t.names.put(t.cb.toText(), "b");
            return t;
        }

        /** A root holding one directory, "Data", with the two files inside it. */
        static Tree nested() throws Exception {
            Tree t = Tree.twoFiles();
            byte[] inner = CarVerifyTest.dirNode(new String[] { "a.bin", "b.bin" },
                new Cid[] { t.ca, t.cb }, new int[] { t.a.length, t.b.length });
            Cid ci = CarVerifyTest.dagCid(inner);
            byte[] outer = CarVerifyTest.dirNode(new String[] { "Data" }, new Cid[] { ci },
                new int[] { inner.length });
            t.root = CarVerifyTest.dagCid(outer);
            t.blocks.put("root", CarVerifyTest.car(t.root,
                new CarVerifyTest.Block[] { new CarVerifyTest.Block(t.root, outer) }));
            t.blocks.put(ci.toText(), CarVerifyTest.car(ci,
                new CarVerifyTest.Block[] { new CarVerifyTest.Block(ci, inner) }));
            t.names.put(ci.toText(), "Data");
            t.names.put(t.ca.toText(), "inner-a");
            t.names.put(t.cb.toText(), "inner-b");
            return t;
        }
    }

    /** A trustless gateway on localhost serving one tree's scoped CARs. */
    private static final class Gateway {
        final HttpServer server;
        final Map<String, Integer> hits = new HashMap<String, Integer>();
        String cutFirstRequestFor;
        private boolean cutDone;

        Gateway(final Tree t) throws IOException {
            server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/ipfs/", new HttpHandler() {
                @Override
                public void handle(HttpExchange x) throws IOException {
                    String path = x.getRequestURI().getPath().substring("/ipfs/".length());
                    String query = x.getRequestURI().getQuery();
                    boolean rootOnly = query != null && query.contains("dag-scope=block");
                    String key = path.equals(t.root.toText()) && rootOnly ? "root" : path;
                    byte[] body = t.blocks.get(key);
                    if (body == null) {
                        x.sendResponseHeaders(404, -1);
                        x.close();
                        return;
                    }
                    String label = key.equals("root") ? "root" : t.names.get(key);
                    Integer n = hits.get(label);
                    hits.put(label, n == null ? 1 : n + 1);

                    boolean cut = label.equals(cutFirstRequestFor) && !cutDone;
                    if (cut) {
                        cutDone = true;
                    }
                    x.getResponseHeaders().add("Content-Type", "application/vnd.ipld.car");
                    x.sendResponseHeaders(200, 0);
                    OutputStream o = x.getResponseBody();
                    o.write(body, 0, cut ? body.length / 2 : body.length);
                    o.close();
                }
            });
            server.start();
            Fetcher.setPrivateGateway("http://127.0.0.1:" + server.getAddress().getPort());
            Fetcher.setPublicGatewaysForTest(new String[0]);
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
