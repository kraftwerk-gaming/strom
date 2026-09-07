package gaming.kraftwerk.strom.ipfs;

import me.zhanghai.android.libarchive.Archive;
import me.zhanghai.android.libarchive.ArchiveEntry;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;

/**
 * Unpacks a {@code tar.zst} payload bundle into a directory.
 *
 * <p>A bundle is one file behind one CID: a tar of the game's tree,
 * compressed with zstd. It replaces a pinned directory tree for the games
 * that ship as one, so the whole payload is one Range-friendly transfer
 * and one decode rather than a walk over thousands of DAG nodes. The
 * archive is verified against its CID by {@link Fetcher} before it lands
 * here, so what this class guards against is not a hostile gateway but a
 * hostile or mistaken archive: an entry name must not be able to write
 * outside the target directory, whatever the tar says.
 *
 * <p>Decoding is libarchive through the me.zhanghai.android.libarchive
 * binding, the one third-party dependency in the APK. zstd is not in the
 * platform ({@code java.util.zip} knows deflate only), and the bundles
 * are made with {@code --long=27}, a 128 MiB window, which zstd's
 * streaming decoder accepts by default ({@code ZSTD_WINDOWLOG_LIMIT_DEFAULT}
 * is 27) and libarchive's zstd filter leaves at the default.
 */
public final class Bundle {
    /** The manifest's {@code payload.format} (and {@code layers[].format}) value this handles. */
    public static final String FORMAT = "tar.zst";

    /**
     * One read from the archive file and one write to disk per chunk; big
     * enough that the JNI round trip per chunk is noise against a
     * multi-gigabyte payload.
     */
    private static final int CHUNK = 256 * 1024;

    /** What extraction reports. Called from the extracting thread; may be null. */
    public interface Progress {
        /**
         * Compressed bytes consumed so far, comparable with the manifest's
         * archive size: uncompressed totals are not published, so this is
         * what a percentage can be built from.
         */
        void bytes(long soFar);

        /**
         * An entry that was not written. Not an error: the tree is still
         * what the archive carries for every file and directory in it.
         */
        void skipped(String name, String why);
    }

    public static final class Stats {
        public long files;
        public long directories;
        public long skipped;
        /** Uncompressed bytes written. */
        public long bytesOut;
    }

    private Bundle() {
    }

    /**
     * Extract {@code archive} into {@code into}, creating it. Regular files
     * and directories only; a file already there is overwritten, which is
     * also what makes a later duplicate entry in the tar win, as it does
     * for tar itself. {@code p} may be null.
     *
     * <p>Binding calls, from Archive.java / ArchiveEntry.java of
     * libarchive-android 1.1.6: readNew, readSupportFormatTar,
     * readSupportFilterZstd, readOpenFileName, readNextHeader (0 at end
     * of archive, unread data of the previous entry is skipped by
     * libarchive itself), readData (fills the buffer from its position to
     * its limit and advances the position; no advance is end of entry),
     * filterBytes(-1) (bytes read from the file, archive_filter_bytes'
     * outermost filter), free (closes first). ArchiveEntry: pathnameUtf8,
     * filetype, hardlinkUtf8.
     */
    public static Stats extract(File archive, File into, Progress p) throws IOException {
        if (!archive.isFile()) {
            throw new IOException("not a " + FORMAT + " file: " + archive);
        }
        if (!into.isDirectory() && !into.mkdirs()) {
            throw new IOException("cannot create " + into);
        }
        Stats st = new Stats();
        ByteBuffer buf = ByteBuffer.allocateDirect(CHUNK);
        long a = Archive.readNew();
        try {
            // Exactly the two decoders a bundle needs. Enabling every format
            // and filter would make a mislabelled payload decode as whatever
            // it happens to be instead of failing with the right message.
            Archive.readSupportFormatTar(a);
            Archive.readSupportFilterZstd(a);
            Archive.readOpenFileName(a, archive.getPath().getBytes(StandardCharsets.UTF_8),
                CHUNK);
            for (long e = Archive.readNextHeader(a); e != 0; e = Archive.readNextHeader(a)) {
                String name = ArchiveEntry.pathnameUtf8(e);
                if (name == null) {
                    // Not valid UTF-8, so there is no file name it could
                    // honestly become; the tree is made from a UTF-8 store
                    // path, so this never happens to a published bundle.
                    skip(p, st, "?", "name is not UTF-8");
                    continue;
                }
                String rel = relative(name);
                if (rel == null) {
                    skip(p, st, name, "escapes the tree");
                    continue;
                }
                int type = ArchiveEntry.filetype(e);
                File target = new File(into, rel);
                if (type == ArchiveEntry.AE_IFDIR) {
                    if (!target.isDirectory() && !target.mkdirs()) {
                        throw new IOException("cannot create " + target);
                    }
                    st.directories++;
                    continue;
                }
                if (type != ArchiveEntry.AE_IFREG) {
                    skip(p, st, name, "not a file or directory");
                    continue;
                }
                File parent = target.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                    throw new IOException("cannot create " + parent);
                }
                if (ArchiveEntry.hardlinkIsSet(e)) {
                    String link = ArchiveEntry.hardlinkUtf8(e);
                    // tar stores the second of two identical files as a link
                    // to the first, and a store tree that has been optimised
                    // has exactly those. Shared storage cannot link, so the
                    // earlier copy is copied again; same bytes on disk.
                    String linkRel = link == null ? null : relative(link);
                    File src = linkRel == null ? null : new File(into, linkRel);
                    if (src == null || !src.isFile()) {
                        skip(p, st, name, "hard link to " + link + ", which is not in the tree");
                        continue;
                    }
                    st.bytesOut += copy(src, target);
                    st.files++;
                    continue;
                }
                st.bytesOut += write(a, target, buf, p);
                st.files++;
            }
            if (p != null) {
                p.bytes(Archive.filterBytes(a, -1));
            }
        } finally {
            Archive.free(a);
        }
        return st;
    }

    /**
     * The path an entry name maps to inside the tree, or null when it
     * must not be written.
     *
     * <p>A bundle is made with {@code tar -c -C tree .}, so names are
     * {@code ./CARS/foo.bin} and the tree root itself is {@code ./}. The
     * rule: split on {@code /}, drop empty and {@code .} components,
     * refuse the name if any component is {@code ..} or if it started with
     * {@code /}. What is left is joined back with {@code /}; the root maps
     * to the empty string. Nothing resolves symlinks because nothing
     * creates any: a link entry is skipped, so a component can only ever
     * be a directory this extraction made or a directory the base already
     * had, and neither points outside it.
     */
    static String relative(String name) {
        if (name.isEmpty() || name.charAt(0) == '/') {
            return null;
        }
        StringBuilder b = new StringBuilder(name.length());
        int start = 0;
        while (start <= name.length()) {
            int end = name.indexOf('/', start);
            if (end < 0) {
                end = name.length();
            }
            String part = name.substring(start, end);
            if (part.equals("..")) {
                return null;
            }
            if (!part.isEmpty() && !part.equals(".")) {
                if (b.length() > 0) {
                    b.append('/');
                }
                b.append(part);
            }
            start = end + 1;
        }
        return b.toString();
    }

    private static void skip(Progress p, Stats st, String name, String why) {
        st.skipped++;
        if (p != null) {
            p.skipped(name, why);
        }
    }

    /**
     * Copy the current entry's data to {@code target}; returns the bytes
     * written. Progress is the archive's compressed position after each
     * chunk, so a single multi-gigabyte file still moves the counter.
     */
    private static long write(long a, File target, ByteBuffer buf, Progress p)
        throws IOException {
        long n = 0;
        FileOutputStream out = new FileOutputStream(target);
        try {
            FileChannel ch = out.getChannel();
            while (true) {
                buf.clear();
                Archive.readData(a, buf);
                if (buf.position() == 0) {
                    break;
                }
                buf.flip();
                while (buf.hasRemaining()) {
                    ch.write(buf);
                }
                n += buf.limit();
                if (p != null) {
                    p.bytes(Archive.filterBytes(a, -1));
                }
            }
        } finally {
            out.close();
        }
        return n;
    }

    private static long copy(File src, File dst) throws IOException {
        long n = 0;
        InputStream in = new FileInputStream(src);
        try {
            OutputStream out = new FileOutputStream(dst);
            try {
                byte[] b = new byte[64 * 1024];
                for (int k = in.read(b); k > 0; k = in.read(b)) {
                    out.write(b, 0, k);
                    n += k;
                }
            } finally {
                out.close();
            }
        } finally {
            in.close();
        }
        return n;
    }
}
