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

/**
 * Pulls a CID from IPFS trustless gateways and unpacks it.
 *
 * <p>Gateways are untrusted transport. The only trusted input is the CID,
 * which comes from the repo, so a gateway that answers with the wrong
 * bytes fails verification in {@link Car} and is simply replaced by the
 * next one in the list.
 */
public final class Fetcher {
    public static final String[] GATEWAYS = {
        "https://trustless-gateway.link",
        "https://ipfs.io",
        "https://dweb.link",
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

    /** The private gateway first when set, then the public list. */
    private static String[] gateways() {
        String p = privateGateway;
        if (p.isEmpty()) {
            return GATEWAYS;
        }
        String[] all = new String[GATEWAYS.length + 1];
        all[0] = p;
        System.arraycopy(GATEWAYS, 0, all, 1, GATEWAYS.length);
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
     * Try each gateway in turn, writing the verified tree to {@code dest}.
     * {@code p} may be null.
     */
    public static UnixFs.Stats fetchAndExtract(String cidText, File dest, Progress p)
        throws IOException {
        Cid root = Cid.fromText(cidText);
        IOException last = null;
        String lastGateway = null;
        String[] list = gateways();
        for (int i = 0; i < list.length; i++) {
            try {
                return attempt(list[i], cidText, root, dest, p);
            } catch (IOException e) {
                if (p != null) {
                    p.gatewayFailed(list[i], e);
                }
                last = e;
                lastGateway = list[i];
                // Whatever this attempt managed to write is unverified in
                // part, so the next gateway has to start from nothing.
                deleteTree(dest);
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
     * Fetch a mod layer and merge it over a game directory that is already
     * there. {@code p} may be null.
     *
     * <p>A layer is not a payload of its own but a partial tree whose files
     * win over the ones already present, which is what reproduces the
     * desktop's overlay merge. It lands on a scratch path beside the game so
     * the whole DAG is verified before a single byte of what the player
     * already has is touched, and so the merge moves entries rather than
     * copying a second multi-gigabyte tree.
     */
    public static UnixFs.Stats fetchAndMerge(String cidText, File dir, String layerName,
        Progress p) throws IOException {
        if (!dir.isDirectory()) {
            throw new IOException("no game directory to merge into: " + dir);
        }
        File part = new File(dir.getAbsolutePath() + ".layer-" + safe(layerName) + ".part");
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

    private static UnixFs.Stats attempt(String gateway, String cidText, Cid root, File dest,
        Progress p) throws IOException {
        URL url = new URL(gateway + "/ipfs/" + cidText + "?format=car&dag-scope=all");
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

            // A fresh counter per attempt: a progress bar should show this
            // download, not the sum of the ones that failed before it.
            InputStream in = new BufferedInputStream(new Counting(conn.getInputStream(), p),
                BUFFER);
            List<Cid> roots = Car.readHeader(in);
            if (!roots.contains(root)) {
                throw new VerifyException("CAR is rooted elsewhere than " + cidText);
            }
            return UnixFs.extractBlocks(in, root, dest);
        } finally {
            conn.disconnect();
        }
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
