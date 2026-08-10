package gaming.kraftwerk.strom.ipfs;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
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
        for (int i = 0; i < GATEWAYS.length; i++) {
            try {
                return attempt(GATEWAYS[i], cidText, root, dest, p);
            } catch (IOException e) {
                last = e;
                lastGateway = GATEWAYS[i];
                // Whatever this attempt managed to write is unverified in
                // part, so the next gateway has to start from nothing.
                delete(dest);
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
    private static void delete(File f) {
        File[] kids = f.listFiles();
        if (kids != null) {
            for (int i = 0; i < kids.length; i++) {
                delete(kids[i]);
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
