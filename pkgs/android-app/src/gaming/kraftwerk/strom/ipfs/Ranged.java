package gaming.kraftwerk.strom.ipfs;

import java.io.EOFException;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.io.RandomAccessFile;
import java.io.Writer;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Future;
import java.util.concurrent.LinkedBlockingDeque;

/**
 * Fetches one UnixFS file by byte range: several gateways at once, each
 * asked for a piece of the file with an HTTP {@code Range}, every leaf
 * checked against its own CID as it lands, and a piece that finished
 * never asked for again -- across gateways, and across restarts of the
 * app.
 *
 * <p>This exists because a gateway generates a CAR on the fly and cuts
 * the stream after a few hundred MB (measured on a 2.7 GiB bundle: every
 * one of six gateways, EOFException between 23 and 321 MiB, nothing
 * kept). A tree got around that by fetching per file; a bundle IS one
 * file, so the unit has to come from inside it. A file's DAG gives one:
 * the leaves are fixed-size raw blocks whose byte offsets follow from
 * their parents' {@code blocksizes}, and a gateway serves the file's
 * bytes with Range support (path-style {@code GET /ipfs/<cid>}, what
 * aria2c races on the desktop). So the DAG's interior -- a few dozen
 * blocks for a multi-GB file at kubo's fan-out of 174 -- is fetched as
 * blocks first, and then the leaves are downloaded as plain bytes, in
 * pieces, and hashed. A piece that cuts costs that piece.
 *
 * <p>The only trusted input is still the CID: the interior blocks are
 * verified by {@link Car}, and a leaf is accepted only if its bytes hash
 * to the digest its parent named. Which gateway sent them is irrelevant.
 */
final class Ranged {
    /**
     * Parallel connections. Gateways rate-limit by request, and each
     * connection here is one long request; four is what a phone's flash
     * and a home uplink absorb without the workers starving each other.
     */
    static final int WORKERS = 4;

    /**
     * Bytes asked for per Range request, rounded up to whole leaves. Big
     * enough that the per-request overhead is noise (a 2.7 GiB bundle is
     * ~350 requests), small enough that a cut stream loses seconds.
     */
    private static final long PIECE_DEFAULT = 8L << 20;
    private static volatile long pieceBytes = PIECE_DEFAULT;

    /** Zero restores the default. Tests only: no other caller. */
    static void setPieceBytesForTest(long n) {
        pieceBytes = n <= 0 ? PIECE_DEFAULT : n;
    }

    /**
     * kubo's largest block is 1 MiB; a layout naming a bigger leaf is not
     * something this repo pins, and bounding it bounds the read buffer.
     */
    private static final int MAX_LEAF = 2 << 20;

    private static final int CONNECT_TIMEOUT_MS = 20000;
    private static final int READ_TIMEOUT_MS = 60000;
    private static final int MAX_REDIRECTS = 5;

    /**
     * A worker stops after this many failures in a row across the gateway
     * list; the fetch fails when every worker has stopped with pieces
     * left. Two full rounds, so a gateway that hiccuped once still gets
     * a second turn before the whole download is declared dead.
     */
    private static final int ROUNDS = 2;

    private Ranged() {
    }

    /** One raw leaf: the block, and where its bytes sit in the file. */
    static final class Leaf {
        final Cid cid;
        final long offset;
        final int size;

        Leaf(Cid cid, long offset, int size) {
            this.cid = cid;
            this.offset = offset;
            this.size = size;
        }
    }

    // ---- layout ----------------------------------------------------------

    /**
     * The leaves of the file rooted at {@code root} whose (verified)
     * block is {@code rootBlock}, in file order, or null when the root is
     * not a chunked file. Interior nodes are fetched level by level on
     * {@code pool}, each through {@link Fetcher#fetchBlock}, so a 65-node
     * interior takes one round trip rather than 65.
     *
     * @throws VerifyException when a leaf is not a raw block (this repo
     *                         pins with raw leaves; a dag-pb leaf would
     *                         need its wrapper rebuilt to be checked, and
     *                         nothing here produces one), or when any
     *                         node's chunks disagree with the size its
     *                         parent declared for it.
     */
    static List<Leaf> layout(Cid root, byte[] rootBlock, Fetcher.Progress p,
        ExecutorService pool) throws IOException {
        List<UnixFs.Chunk> top = UnixFs.fileChunks(root, rootBlock);
        if (top == null) {
            return null;
        }
        List<Leaf> out = new ArrayList<Leaf>();
        expand(top, 0, out, p, pool);
        return out;
    }

    private static void expand(List<UnixFs.Chunk> chunks, long offset, List<Leaf> out,
        final Fetcher.Progress p, ExecutorService pool) throws IOException {
        // Interior children first, all at once; leaves need no request.
        List<Future<byte[]>> blocks = new ArrayList<Future<byte[]>>(chunks.size());
        for (int i = 0; i < chunks.size(); i++) {
            final UnixFs.Chunk c = chunks.get(i);
            if (c.cid.codec == Cid.CODEC_DAG_PB) {
                blocks.add(pool.submit(new Callable<byte[]>() {
                    @Override
                    public byte[] call() throws IOException {
                        return Fetcher.fetchBlock(c.cid.toText(), c.cid, p);
                    }
                }));
            } else {
                blocks.add(null);
            }
        }
        for (int i = 0; i < chunks.size(); i++) {
            UnixFs.Chunk c = chunks.get(i);
            Future<byte[]> f = blocks.get(i);
            if (f == null) {
                if (c.cid.codec != Cid.CODEC_RAW) {
                    throw new VerifyException("file leaf " + c.cid + " is not a raw block");
                }
                if (c.size > MAX_LEAF) {
                    throw new VerifyException("file leaf of " + c.size + " bytes");
                }
                out.add(new Leaf(c.cid, offset, (int) c.size));
                offset += c.size;
                continue;
            }
            byte[] block;
            try {
                block = f.get();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IOException("interrupted while reading the file layout", e);
            } catch (ExecutionException e) {
                Throwable t = e.getCause();
                if (t instanceof IOException) {
                    throw (IOException) t;
                }
                throw new IOException(t);
            }
            List<UnixFs.Chunk> kids = UnixFs.fileChunks(c.cid, block);
            if (kids == null) {
                throw new VerifyException("file node " + c.cid + " is not a chunked file");
            }
            long declared = 0;
            for (int k = 0; k < kids.size(); k++) {
                declared += kids.get(k).size;
            }
            if (declared != c.size) {
                throw new VerifyException("file node " + c.cid + " holds " + declared
                    + " bytes where its parent declared " + c.size);
            }
            expand(kids, offset, out, p, pool);
            offset += c.size;
        }
    }

    // ---- pieces ----------------------------------------------------------

    /** A run of whole leaves asked for in one Range request. */
    private static final class Piece {
        final int index;
        final int firstLeaf;
        final int endLeaf;
        final long offset;
        final long size;

        Piece(int index, int firstLeaf, int endLeaf, long offset, long size) {
            this.index = index;
            this.firstLeaf = firstLeaf;
            this.endLeaf = endLeaf;
            this.offset = offset;
            this.size = size;
        }
    }

    private static List<Piece> pieces(List<Leaf> leaves) {
        long max = pieceBytes;
        List<Piece> out = new ArrayList<Piece>();
        int first = 0;
        while (first < leaves.size()) {
            int end = first;
            long size = 0;
            while (end < leaves.size() && (size == 0 || size + leaves.get(end).size <= max)) {
                size += leaves.get(end).size;
                end++;
            }
            out.add(new Piece(out.size(), first, end, leaves.get(first).offset, size));
            first = end;
        }
        return out;
    }

    /**
     * What finished, beside the file: the CID on the first line so a
     * state left by another payload on the same path is not believed,
     * then one character per piece. Rewritten whole after every piece --
     * it is a few hundred bytes -- and renamed into place, so a kill
     * mid-write leaves the previous state rather than a torn one.
     */
    static File stateFile(File dest) {
        return new File(dest.getAbsolutePath() + ".pieces");
    }

    private static boolean[] loadState(File state, String cidText, int pieces)
        throws IOException {
        boolean[] done = new boolean[pieces];
        if (!state.isFile()) {
            return done;
        }
        String[] lines = new String(Files.readAllBytes(state.toPath()), StandardCharsets.UTF_8)
            .split("\n");
        if (lines.length < 2 || !lines[0].equals(cidText) || lines[1].length() != pieces) {
            return done;
        }
        for (int i = 0; i < pieces; i++) {
            done[i] = lines[1].charAt(i) == '1';
        }
        return done;
    }

    private static void saveState(File state, String cidText, boolean[] done)
        throws IOException {
        File tmp = new File(state.getAbsolutePath() + ".tmp");
        Writer w = new OutputStreamWriter(new FileOutputStream(tmp), StandardCharsets.UTF_8);
        try {
            w.write(cidText);
            w.write('\n');
            for (int i = 0; i < done.length; i++) {
                w.write(done[i] ? '1' : '0');
            }
            w.write('\n');
        } finally {
            w.close();
        }
        if (!tmp.renameTo(state)) {
            throw new IOException("cannot write " + state);
        }
    }

    // ---- the download ----------------------------------------------------

    /**
     * Download the file described by {@code leaves} to {@code dest}, all
     * of it verified, resuming whatever an earlier attempt left there.
     * {@code gateways} is tried in order by each worker, starting at a
     * different one per worker; {@code p} may be null.
     */
    static UnixFs.Stats fetch(final String cidText, final List<Leaf> leaves, final File dest,
        Fetcher.Progress p, final String[] gateways) throws IOException {
        if (gateways.length == 0) {
            throw new IOException("no gateways configured");
        }
        final List<Piece> pieces = pieces(leaves);
        final long total = leaves.isEmpty() ? 0
            : leaves.get(leaves.size() - 1).offset + leaves.get(leaves.size() - 1).size;
        final File state = stateFile(dest);
        final boolean[] done = loadState(state, cidText, pieces.size());
        if (!dest.isFile() || dest.length() != total) {
            // Nothing of a file of another length is worth keeping, and a
            // state that claims otherwise is from another file.
            Arrays.fill(done, false);
            Fetcher.deleteTree(dest);
        }
        RandomAccessFile sizing = new RandomAccessFile(dest, "rw");
        try {
            if (sizing.length() != total) {
                sizing.setLength(total);
            }
        } finally {
            sizing.close();
        }

        final Shared shared = new Shared(p, state, cidText, done, total);
        final LinkedBlockingDeque<Piece> queue = new LinkedBlockingDeque<Piece>();
        for (int i = 0; i < pieces.size(); i++) {
            if (done[i]) {
                shared.verified += pieces.get(i).size;
            } else {
                queue.add(pieces.get(i));
            }
        }
        shared.report(0);

        int n = Math.min(WORKERS, Math.max(1, queue.size()));
        Worker[] workers = new Worker[n];
        for (int i = 0; i < n; i++) {
            workers[i] = new Worker(i, gateways, leaves, queue, dest, shared);
            workers[i].start();
        }
        for (int i = 0; i < n; i++) {
            try {
                workers[i].join();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                for (int k = 0; k < n; k++) {
                    workers[k].interrupt();
                }
                throw new IOException("interrupted while fetching " + cidText, e);
            }
        }

        if (!queue.isEmpty()) {
            IOException last = null;
            String lastGateway = null;
            for (int i = 0; i < n; i++) {
                if (workers[i].last != null) {
                    last = workers[i].last;
                    lastGateway = workers[i].lastGateway;
                }
            }
            if (last == null) {
                throw new IOException("pieces left with no worker failure to blame");
            }
            String message = lastGateway + ": " + last.getMessage();
            if (last instanceof VerifyException) {
                throw new VerifyException(message);
            }
            throw new IOException(message, last);
        }
        state.delete();
        UnixFs.Stats st = new UnixFs.Stats();
        st.blocks = leaves.size();
        st.bytesOut = total;
        st.files = 1;
        return st;
    }

    /** What the workers share: the progress line and the finished map. */
    private static final class Shared {
        private final Fetcher.Progress p;
        private final File state;
        final String cidText;
        private final boolean[] done;
        private final long total;
        long verified;
        private long lastReport;
        private String via;

        Shared(Fetcher.Progress p, File state, String cidText, boolean[] done, long total) {
            this.p = p;
            this.state = state;
            this.cidText = cidText;
            this.done = done;
            this.total = total;
        }

        /**
         * Throttled: four workers each report per leaf, and every report
         * is a line posted to the UI thread.
         */
        synchronized void report(long delta) {
            verified += delta;
            long now = System.currentTimeMillis();
            if (p != null && (now - lastReport >= 250 || verified == total)) {
                lastReport = now;
                p.bytes(verified);
            }
        }

        synchronized void finished(Piece piece) throws IOException {
            done[piece.index] = true;
            saveState(state, cidText, done);
        }

        /** The status line names one gateway; the most recent switch wins. */
        synchronized void trying(String gateway) {
            if (p != null && !gateway.equals(via)) {
                via = gateway;
                p.trying(gateway);
            }
        }

        synchronized void failed(String gateway, IOException e) {
            if (p != null) {
                p.gatewayFailed(gateway, e);
            }
        }
    }

    private static final class Worker extends Thread {
        private final String[] gateways;
        private final List<Leaf> leaves;
        private final LinkedBlockingDeque<Piece> queue;
        private final File dest;
        private final Shared shared;
        private int gateway;
        IOException last;
        String lastGateway;

        Worker(int index, String[] gateways, List<Leaf> leaves, LinkedBlockingDeque<Piece> queue,
            File dest, Shared shared) {
            super("strom-fetch-" + index);
            this.gateways = gateways;
            this.leaves = leaves;
            this.queue = queue;
            this.dest = dest;
            this.shared = shared;
            this.gateway = index % gateways.length;
        }

        @Override
        public void run() {
            byte[] buf = new byte[MAX_LEAF];
            MessageDigest md = sha256();
            int failures = 0;
            try {
                RandomAccessFile out = new RandomAccessFile(dest, "rw");
                try {
                    while (failures < ROUNDS * gateways.length && !isInterrupted()) {
                        Piece piece = queue.pollFirst();
                        if (piece == null) {
                            return;
                        }
                        String gw = gateways[gateway];
                        shared.trying(gw);
                        try {
                            fetchPiece(gw, piece, out, buf, md);
                            shared.finished(piece);
                            failures = 0;
                        } catch (IOException e) {
                            // Back to the front: the file fills in order,
                            // which is what a partially fetched file is
                            // worth if the app is killed.
                            queue.addFirst(piece);
                            shared.failed(gw, e);
                            last = e;
                            lastGateway = gw;
                            failures++;
                            gateway = (gateway + 1) % gateways.length;
                        }
                    }
                } finally {
                    out.close();
                }
            } catch (IOException e) {
                last = e;
                lastGateway = gateways[gateway];
            }
        }

        private void fetchPiece(String gw, Piece piece, RandomAccessFile out, byte[] buf,
            MessageDigest md) throws IOException {
            HttpURLConnection conn = open(gw, shared.cidText, piece.offset, piece.size);
            try {
                InputStream in = conn.getInputStream();
                try {
                    for (int i = piece.firstLeaf; i < piece.endLeaf; i++) {
                        Leaf leaf = leaves.get(i);
                        readFully(in, buf, leaf.size);
                        md.reset();
                        md.update(buf, 0, leaf.size);
                        if (!Arrays.equals(md.digest(), leaf.cid.digest)) {
                            throw new VerifyException("bytes at " + leaf.offset
                                + " do not hash to " + leaf.cid);
                        }
                        // Written only once verified, so the file on disk
                        // never holds a byte the CID did not vouch for.
                        out.seek(leaf.offset);
                        out.write(buf, 0, leaf.size);
                        shared.report(leaf.size);
                    }
                } finally {
                    in.close();
                }
            } finally {
                conn.disconnect();
            }
        }
    }

    /**
     * One Range request for {@code size} bytes at {@code offset}, with
     * redirects followed by hand so the Range header survives them
     * (public gateways bounce a path request to a subdomain, and
     * whether the platform re-sends request properties across that
     * hop is not something to depend on). Anything but 206 is a
     * failure: a 200 would be the whole file, which is what this class
     * exists not to ask for.
     */
    private static HttpURLConnection open(String gateway, String cidText, long offset,
        long size) throws IOException {
        URL url = new URL(gateway + "/ipfs/" + cidText);
        for (int hop = 0; ; hop++) {
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            try {
                conn.setInstanceFollowRedirects(false);
                conn.setRequestMethod("GET");
                conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
                conn.setReadTimeout(READ_TIMEOUT_MS);
                conn.setRequestProperty("Range",
                    "bytes=" + offset + "-" + (offset + size - 1));
                // As in Fetcher: Cloudflare-fronted gateways 403 unknown agents.
                conn.setRequestProperty("User-Agent", "curl/8.4.0");
                int code = conn.getResponseCode();
                if (code == HttpURLConnection.HTTP_MOVED_PERM
                    || code == HttpURLConnection.HTTP_MOVED_TEMP
                    || code == HttpURLConnection.HTTP_SEE_OTHER
                    || code == 307 || code == 308) {
                    String to = conn.getHeaderField("Location");
                    if (to == null || hop >= MAX_REDIRECTS) {
                        throw new IOException("HTTP " + code + " without a usable Location");
                    }
                    url = new URL(url, to);
                    conn.disconnect();
                    continue;
                }
                if (code != HttpURLConnection.HTTP_PARTIAL) {
                    throw new IOException("HTTP " + code + " " + conn.getResponseMessage()
                        + " to a Range request");
                }
                return conn;
            } catch (IOException e) {
                conn.disconnect();
                throw e;
            }
        }
    }

    private static void readFully(InputStream in, byte[] buf, int len) throws IOException {
        int have = 0;
        while (have < len) {
            int n = in.read(buf, have, len - have);
            if (n < 0) {
                throw new EOFException("stream ended " + (len - have) + " bytes short of a leaf");
            }
            have += n;
        }
    }

    private static MessageDigest sha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
