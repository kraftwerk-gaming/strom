package gaming.kraftwerk.strom.ipfs;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Pulls a CID from IPFS trustless gateways and unpacks it.
 *
 * <p>Gateways are untrusted transport. The only trusted input is the CID,
 * which comes from the repo, so a gateway that answers with the wrong
 * bytes fails verification in {@link Car} and is simply replaced by the
 * next one in the list.
 */
public final class Fetcher {
    /**
     * Order is measured, not alphabetical. Against a freshly pinned CID
     * that only one DHT provider announces, pinata and nftstorage.link
     * resolve it cold (root block in 8 s and 28 s, a 53 MiB CAR in ~50 s);
     * ipfs.io, dweb.link, w3s.link and trustless-gateway.link answer 504
     * after their ~28 s budget until something has warmed their cache,
     * after which they are the fastest (8 s for the same CAR). So the two
     * that find content lead, and the fast-when-warm ones follow.
     */
    public static final String[] GATEWAYS = {
        "https://gateway.pinata.cloud",
        "https://nftstorage.link",
        "https://ipfs.io",
        "https://dweb.link",
        "https://trustless-gateway.link",
        "https://w3s.link",
    };

    /**
     * A private or LAN gateway, tried before the public ones. The desktop
     * has the same escape hatch as STROM_IPFS_GATEWAYS (AGENTS.md); this is
     * the phone's, for a local mirror, a LAN cache, or a payload that is
     * not on public infrastructure yet.
     *
     * <p>Untrusted like every other gateway: the CID is the only trusted
     * input, so wrong bytes fail verification and the next gateway is
     * tried. That is what makes pointing this at anything safe.
     */
    private static volatile String privateGateway = "";

    public static void setPrivateGateway(String g) {
        String v = g == null ? "" : g.trim();
        while (v.endsWith("/")) {
            v = v.substring(0, v.length() - 1);
        }
        privateGateway = v;
    }

    /** The public list, or a test's replacement for it. */
    private static volatile String[] publicGateways = GATEWAYS;

    /** Null restores the built-in list. Tests only: no other caller. */
    static void setPublicGatewaysForTest(String[] list) {
        publicGateways = list == null ? GATEWAYS : list;
    }

    /** The private gateway first when set, then the public list. */
    private static String[] gateways() {
        String p = privateGateway;
        String[] pub = publicGateways;
        if (p.isEmpty()) {
            return pub;
        }
        String[] all = new String[pub.length + 1];
        all[0] = p;
        System.arraycopy(pub, 0, all, 1, pub.length);
        return all;
    }

    private static final int CONNECT_TIMEOUT_MS = 20000;
    /**
     * Per read, not for the transfer as a whole: a game payload is
     * gigabytes and takes as long as it takes, but a gateway that stops
     * sending for a minute is dead and the next one should get a turn.
     */
    private static final int READ_TIMEOUT_MS = 60000;
    private static final int BUFFER = 64 * 1024;

    public interface Progress {
        void bytes(long soFar);

        /**
         * A gateway is about to be asked. Shown, not only logged: until
         * the first bytes arrive the byte counter has nothing to say, and
         * a gateway that takes 30 s to answer 504 is indistinguishable
         * from a stall unless its name is on screen.
         */
        void trying(String gateway);

        /**
         * A gateway gave up and the next one is about to start from
         * nothing. Without this the only visible reason is whichever
         * gateway came LAST in the list, and the interesting failure is
         * usually earlier -- a preferred private mirror that dropped the
         * stream.
         */
        void gatewayFailed(String gateway, IOException e);
    }

    private Fetcher() {
    }

    /**
     * Write the verified tree behind {@code cidText} to {@code dest}.
     * {@code p} may be null.
     *
     * <p>A directory is walked node by node and each file fetched as its
     * own CAR; a file that finished is not fetched again. A gateway
     * generates a CAR on the fly (accept-ranges: none), so the only
     * resume unit it offers is the DAG, and a 3.6 GB tree in one HTTP
     * response did not survive the connection -- measured: EOFException
     * mid-stream, the whole download gone, every retry from zero. Per
     * top-level entry was not enough either: FF8's 57 entries
     * include one directory holding 3 GB, and that stream cut the same
     * way. So the unit is the file, the finest thing a gateway serves in
     * one CAR. A file payload (a ROM) is one stream, as before.
     *
     * <p>What this gives up: the walker serves a repeated block from where
     * it landed earlier in the same walk, and that memory is per walk, so
     * a block two files share is transferred twice. Bandwidth, not
     * correctness.
     */
    public static UnixFs.Stats fetchAndExtract(String cidText, File dest, Progress p)
        throws IOException {
        Cid root = Cid.fromText(cidText);
        byte[] rootBlock = fetchBlock(cidText, root, p);
        List<UnixFs.Entry> entries = UnixFs.directoryEntries(root, rootBlock);
        if (entries == null) {
            return race(cidText, root, dest, p, "all");
        }

        File done = new File(dest.getAbsolutePath() + ".done");
        if (!done.isDirectory() && !done.mkdirs()) {
            throw new IOException("cannot create " + done);
        }
        Tally tally = new Tally(p);
        fetchDirectory(entries, dest, done, tally);
        deleteTree(done);
        return tally.total;
    }

    /**
     * One running count across the files, so the status line and its
     * percentage are the tree's, not the file's. Per attempt the counter
     * restarts at zero (a failed gateway's bytes are gone), so the offset
     * is what finished files delivered, and a restarted attempt is
     * reported from that offset rather than from what the failed one had
     * reached -- the count can pause, never run backwards.
     */
    private static final class Tally implements Progress {
        final Progress p;
        final UnixFs.Stats total = new UnixFs.Stats();
        long before;

        Tally(Progress p) {
            this.p = p;
        }

        @Override
        public void bytes(long soFar) {
            if (p != null) {
                p.bytes(before + soFar);
            }
        }

        @Override
        public void trying(String gateway) {
            if (p != null) {
                p.trying(gateway);
            }
        }

        @Override
        public void gatewayFailed(String gateway, IOException e) {
            if (p != null) {
                p.gatewayFailed(gateway, e);
            }
        }

        void finished(UnixFs.Stats st) {
            before += st.bytesOut;
            total.blocks += st.blocks;
            total.bytesOut += st.bytesOut;
            total.files += st.files;
            total.duplicates += st.duplicates;
        }
    }

    private static void fetchDirectory(List<UnixFs.Entry> entries, File dir, File done,
        Tally tally) throws IOException {
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new IOException("cannot create " + dir);
        }
        for (int i = 0; i < entries.size(); i++) {
            UnixFs.Entry e = entries.get(i);
            File target = new File(dir, e.name);
            File marker = new File(done, e.name);
            if (marker.isFile() && target.exists()) {
                tally.before += sizeOf(target);
                continue;
            }
            String cidText = e.cid.toText();
            byte[] block = fetchBlock(cidText, e.cid, tally);
            List<UnixFs.Entry> kids = UnixFs.directoryEntries(e.cid, block);
            if (kids != null) {
                if (!marker.isDirectory() && !marker.mkdirs()) {
                    throw new IOException("cannot create " + marker);
                }
                fetchDirectory(kids, target, marker, tally);
                continue;
            }
            deleteTree(target);
            UnixFs.Stats st = race(cidText, e.cid, target, tally, "all");
            tally.finished(st);
            new java.io.FileOutputStream(marker).close();
        }
    }

    /** The one block behind a CID, verified, through the first gateway that has it. */
    static byte[] fetchBlock(String cidText, Cid cid, Progress p) throws IOException {
        final byte[][] got = new byte[1][];
        raceCar(cidText, cid, p, "block", new Car.BlockSink() {
            @Override
            public void block(Cid c, byte[] data) throws IOException {
                if (!c.equals(cid) || got[0] != null) {
                    throw new VerifyException("root CAR carries more than the root block");
                }
                got[0] = data;
            }
        });
        if (got[0] == null) {
            throw new VerifyException("root CAR carries no block");
        }
        return got[0];
    }

    /** Try each gateway in turn until one delivers the whole subtree to {@code dest}. */
    private static UnixFs.Stats race(String cidText, Cid root, File dest, Progress p,
        String scope) throws IOException {
        final UnixFs.Stats[] out = new UnixFs.Stats[1];
        final File target = dest;
        raceCar(cidText, root, p, scope, null, new Attempt() {
            @Override
            public void run(InputStream in) throws IOException {
                out[0] = UnixFs.extractBlocks(in, root, target);
            }

            @Override
            public void failed() {
                // Whatever this attempt managed to write is unverified in
                // part, so the next gateway has to start from nothing.
                deleteTree(target);
            }
        });
        return out[0];
    }

    private interface Attempt {
        void run(InputStream in) throws IOException;

        void failed();
    }

    private static void raceCar(String cidText, Cid root, Progress p, String scope,
        Car.BlockSink sink) throws IOException {
        raceCar(cidText, root, p, scope, sink, null);
    }

    /**
     * Where the next race starts: the gateway that served last. The list
     * order is right cold, but a race per block re-pays every leading
     * gateway's timeout per block -- measured: 65 interior blocks of a
     * bundle spent 7.5 minutes on pinata read timeouts before the first
     * byte of the file. A gateway that has just answered is the one to
     * ask next; when it fails the race wraps through the rest as before.
     */
    private static volatile String served = "";

    private static void raceCar(String cidText, Cid root, Progress p, String scope,
        final Car.BlockSink sink, Attempt attempt) throws IOException {
        IOException last = null;
        String lastGateway = null;
        String[] list = gateways();
        int start = 0;
        for (int i = 0; i < list.length; i++) {
            if (list[i].equals(served)) {
                start = i;
            }
        }
        for (int k = 0; k < list.length; k++) {
            String gw = list[(start + k) % list.length];
            try {
                if (p != null) {
                    p.trying(gw);
                }
                InputStream in = open(gw, cidText, root, scope, p);
                try {
                    if (attempt != null) {
                        attempt.run(in);
                    } else {
                        Car.streamBlocks(in, sink);
                    }
                } finally {
                    in.close();
                }
                served = gw;
                return;
            } catch (IOException e) {
                if (p != null) {
                    p.gatewayFailed(gw, e);
                }
                last = e;
                lastGateway = gw;
                if (attempt != null) {
                    attempt.failed();
                }
            }
        }
        if (last == null) {
            throw new IOException("no gateways configured");
        }
        String message = lastGateway + ": " + last.getMessage();
        if (last instanceof VerifyException) {
            throw new VerifyException(message);
        }
        throw new IOException(message, last);
    }

    /**
     * Write the verified file behind {@code cidText} to {@code dest}: a
     * bundle, or any single-file payload big enough to be chunked.
     * {@code p} may be null.
     *
     * <p>Not one CAR stream, which no public gateway keeps open for a
     * multi-GB file (measured, see {@link Ranged}): the file's interior
     * DAG nodes are fetched as blocks, and its raw leaves by HTTP Range,
     * several gateways at once, each leaf hashed on arrival. A piece that
     * finished is recorded beside {@code dest} and not asked for again,
     * so a cut stream, a gateway that quit, or an app that was killed
     * costs at most one piece. A file too small to have leaves -- one
     * whose content sits in its root block -- is one CAR, as a ROM is.
     */
    public static UnixFs.Stats fetchFile(String cidText, File dest, Progress p)
        throws IOException {
        Cid root = Cid.fromText(cidText);
        // The interior blocks are kilobytes and the counter is the file's:
        // they would show as a few KiB that the download then "loses" when
        // its own count starts. Their gateways and failures still show.
        Progress layout = p == null ? null : new Progress() {
            @Override
            public void bytes(long soFar) {
            }

            @Override
            public void trying(String gateway) {
                p.trying(gateway);
            }

            @Override
            public void gatewayFailed(String gateway, IOException e) {
                p.gatewayFailed(gateway, e);
            }
        };
        byte[] rootBlock = fetchBlock(cidText, root, layout);
        ExecutorService pool = Executors.newFixedThreadPool(Ranged.WORKERS);
        List<Ranged.Leaf> leaves;
        try {
            leaves = Ranged.layout(root, rootBlock, layout, pool);
        } finally {
            pool.shutdownNow();
        }
        if (leaves == null) {
            deleteTree(dest);
            Ranged.stateFile(dest).delete();
            return race(cidText, root, dest, p, "all");
        }
        return Ranged.fetch(cidText, leaves, dest, p, gateways());
    }

    /**
     * Fetch a mod layer and merge it over a game directory that is already
     * there. {@code format} is the layer's manifest {@code format}, null
     * for a pinned tree; {@code p} and {@code unpack} may be null.
     *
     * <p>A layer is not a payload of its own but a partial tree whose files
     * win over the ones already present, which is what reproduces the
     * desktop's overlay merge. It lands on a scratch path beside the game so
     * the whole DAG is verified before a single byte of what the player
     * already has is touched, and so the merge moves entries rather than
     * copying a second multi-gigabyte tree. A {@link Bundle} layer lands as
     * one archive and is unpacked onto a second scratch path first, so the
     * same holds for it: the base is touched only once the whole layer has
     * decoded, and then by moving entries.
     */
    public static UnixFs.Stats fetchAndMerge(String cidText, String format, File dir,
        String layerName, Progress p, Bundle.Progress unpack) throws IOException {
        if (!dir.isDirectory()) {
            throw new IOException("no game directory to merge into: " + dir);
        }
        File part = new File(dir.getAbsolutePath() + ".layer-" + safe(layerName) + ".part");
        File tree = new File(part.getAbsolutePath() + ".tree");
        deleteTree(tree);
        if (Bundle.FORMAT.equals(format)) {
            // The archive is fetched by range and resumes from what an
            // earlier attempt verified, so it stays on a failure; only a
            // half-unpacked tree is scratch.
            UnixFs.Stats st = fetchFile(cidText, part, p);
            try {
                Bundle.extract(part, tree, unpack);
                merge(tree, dir);
            } finally {
                deleteTree(tree);
            }
            deleteTree(part);
            return st;
        }
        deleteTree(part);
        UnixFs.Stats st = fetchAndExtract(cidText, part, p);
        try {
            merge(part, dir);
        } finally {
            // Whatever a failed merge left behind is a partial copy of bytes
            // that are still on a gateway; the next attempt refetches.
            deleteTree(part);
        }
        return st;
    }

    /** A layer name is a Nix pname, but a scratch path must not be steerable. */
    private static String safe(String name) {
        StringBuilder b = new StringBuilder(name.length());
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
            b.append(ok ? c : '-');
        }
        return b.toString();
    }

    /** Move {@code src} onto {@code dst}, entry by entry, src winning. */
    private static void merge(File src, File dst) throws IOException {
        if (src.isDirectory()) {
            if (dst.exists() && !dst.isDirectory()) {
                deleteTree(dst);
            }
            if (!dst.isDirectory() && !dst.mkdirs()) {
                throw new IOException("cannot create " + dst);
            }
            File[] kids = src.listFiles();
            if (kids == null) {
                throw new IOException("cannot list " + src);
            }
            for (int i = 0; i < kids.length; i++) {
                merge(kids[i], new File(dst, kids[i].getName()));
            }
            return;
        }
        if (dst.exists()) {
            deleteTree(dst);
        }
        if (!src.renameTo(dst)) {
            // Only when the scratch path and the game ended up on different
            // mounts, which the shared parent makes unlikely but not
            // impossible on a device with an SD card.
            copy(src, dst);
        }
    }

    private static void copy(File src, File dst) throws IOException {
        InputStream in = new FileInputStream(src);
        try {
            OutputStream out = new FileOutputStream(dst);
            try {
                byte[] buf = new byte[BUFFER];
                for (int n = in.read(buf); n > 0; n = in.read(buf)) {
                    out.write(buf, 0, n);
                }
            } finally {
                out.close();
            }
        } finally {
            in.close();
        }
    }

    /**
     * Open a CAR for {@code root} at {@code scope} ("all" for the subtree,
     * "block" for the one node) from one gateway, with the header read
     * and checked to be rooted there. Closing the stream disconnects.
     */
    private static InputStream open(String gateway, String cidText, Cid root, String scope,
        Progress p) throws IOException {
        URL url = new URL(gateway + "/ipfs/" + cidText + "?format=car&dag-scope=" + scope);
        HttpURLConnection first;
        try {
            first = request(url);
        } catch (java.net.UnknownHostException e) {
            // A name that did not resolve is not a gateway without the
            // content; it is a lookup that missed, and Android caches the
            // miss. Measured: the first gateway in the list lost its one
            // attempt to a transient miss on a device that resolved the
            // same name a minute later, and the ones it fell through to
            // could not serve the CID at all. One retry after a pause,
            // then the failure is real.
            try {
                Thread.sleep(3000);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                throw e;
            }
            first = request(url);
        }
        final HttpURLConnection conn = first;
        try {
            // A fresh counter per attempt: a progress bar should show this
            // download, not the sum of the ones that failed before it.
            InputStream in = new BufferedInputStream(new Counting(conn.getInputStream(), p),
                BUFFER) {
                @Override
                public void close() throws IOException {
                    try {
                        super.close();
                    } finally {
                        conn.disconnect();
                    }
                }
            };
            List<Cid> roots = Car.readHeader(in);
            if (!roots.contains(root)) {
                in.close();
                throw new VerifyException("CAR is rooted elsewhere than " + cidText);
            }
            return in;
        } catch (IOException e) {
            conn.disconnect();
            throw e;
        }
    }

    /** Send the CAR request and read the status; the body is untouched. */
    private static HttpURLConnection request(URL url) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        try {
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
            conn.setReadTimeout(READ_TIMEOUT_MS);
            conn.setRequestProperty("Accept", "application/vnd.ipld.car");
            // Cloudflare-fronted gateways answer 403 to user agents they do
            // not recognise. Measured on ipfs.io: the prototype's own agent
            // string was rejected, curl's is served.
            conn.setRequestProperty("User-Agent", "curl/8.4.0");
            int code = conn.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                throw new IOException("HTTP " + code + " " + conn.getResponseMessage());
            }
            return conn;
        } catch (IOException e) {
            conn.disconnect();
            throw e;
        }
    }

    /** Bytes under a path: what a finished entry contributed to the tree. */
    private static long sizeOf(File f) {
        if (f.isFile()) {
            return f.length();
        }
        File[] kids = f.listFiles();
        long n = 0;
        if (kids != null) {
            for (int i = 0; i < kids.length; i++) {
                n += sizeOf(kids[i]);
            }
        }
        return n;
    }

    /** Remove a file, or a directory tree, that must not be kept. */
    public static void deleteTree(File f) {
        File[] kids = f.listFiles();
        if (kids != null) {
            for (int i = 0; i < kids.length; i++) {
                deleteTree(kids[i]);
            }
        }
        // Nothing useful to do if this fails: the next attempt will
        // overwrite what it can, and verification still gates the result.
        f.delete();
    }

    private static final class Counting extends FilterInputStream {
        private final Progress p;
        private long total;

        Counting(InputStream in, Progress p) {
            super(in);
            this.p = p;
        }

        @Override
        public int read() throws IOException {
            int b = in.read();
            if (b >= 0) {
                total++;
                report();
            }
            return b;
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            int n = in.read(b, off, len);
            if (n > 0) {
                total += n;
                report();
            }
            return n;
        }

        private void report() {
            if (p != null) {
                p.bytes(total);
            }
        }
    }
}
