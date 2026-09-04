package gaming.kraftwerk.strom.ipfs;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;

/**
 * Tests the verifier that protects everything the client downloads.
 *
 * <p>A gateway is untrusted transport: the only thing vouching for a
 * multi-gigabyte game is that every block hashes to the CID that
 * referenced it. If that check is wrong, a hostile or broken gateway can
 * hand a phone anything at all, so it gets a test that actually tries to
 * cheat rather than one that only walks the happy path.
 *
 * <p>Plain main(), no JUnit: the client has no third-party dependencies
 * and this runs under the same javac the APK is built with.
 */
public final class CarVerifyTest {
    private static int failures = 0;

    public static void main(String[] args) throws Exception {
        roundTripsASingleRawBlock();
        roundTripsADirectoryTree();
        rejectsATamperedLeaf();
        rejectsATamperedInteriorNode();
        rejectsATruncatedCar();
        rejectsARootThatWasNotRequested();
        cidTextRoundTrips();
        reassemblesAFileWhoseChunksRepeat();
        servesARepeatFromDiskHoweverFarApart();

        if (failures > 0) {
            System.err.println(failures + " test(s) failed");
            System.exit(1);
        }
        System.out.println("all verifier tests passed");
    }

    // ---- tests -----------------------------------------------------------

    private static void roundTripsASingleRawBlock() throws Exception {
        byte[] content = "the quick brown fox".getBytes("UTF-8");
        Cid cid = rawCid(content);
        byte[] car = car(cid, new Block[] { new Block(cid, content) });

        File out = tmp("single");
        UnixFs.Stats st = UnixFs.extract(new ByteArrayInputStream(car), cid, out);

        check("single raw block writes its bytes",
            java.util.Arrays.equals(content, Files.readAllBytes(out.toPath())));
        check("single raw block counts one block", st.blocks == 1);
    }

    private static void roundTripsADirectoryTree() throws Exception {
        byte[] a = "alpha".getBytes("UTF-8");
        byte[] b = "beta".getBytes("UTF-8");
        Cid ca = rawCid(a);
        Cid cb = rawCid(b);
        byte[] dir = dirNode(new String[] { "a.txt", "b.txt" }, new Cid[] { ca, cb },
            new int[] { a.length, b.length });
        Cid cd = dagCid(dir);

        // DFS order: parent before children, which is what the client relies
        // on to stream rather than buffer.
        byte[] car = car(cd, new Block[] {
            new Block(cd, dir), new Block(ca, a), new Block(cb, b),
        });

        File out = tmp("tree");
        UnixFs.Stats st = UnixFs.extract(new ByteArrayInputStream(car), cd, out);

        check("directory writes both files", st.files == 2);
        check("directory file a survives",
            java.util.Arrays.equals(a, Files.readAllBytes(new File(out, "a.txt").toPath())));
        check("directory file b survives",
            java.util.Arrays.equals(b, Files.readAllBytes(new File(out, "b.txt").toPath())));
    }

    /**
     * A chunked file whose chunks are not all distinct.
     *
     * <p>Trustless gateways serve {@code dups=n}: a block is transmitted
     * once however many times the DAG points at it. Real payloads point at
     * the same block constantly, because a ROM's padding chunks are byte
     * identical and so share a CID. The extractor originally assumed one
     * arriving block per reference and failed such a file with "CAR ended
     * with N block(s) unaccounted for" -- on real data that was 2 blocks
     * for a 32 MiB ROM and 111 for a 128 MiB one, so most of the published
     * catalogue could not be fetched at all.
     */
    private static void reassemblesAFileWhoseChunksRepeat() throws Exception {
        byte[] padding = new byte[64];      // the repeated chunk
        java.util.Arrays.fill(padding, (byte) 0xff);
        byte[] head = "header".getBytes("UTF-8");

        Cid cHead = rawCid(head);
        Cid cPad = rawCid(padding);
        // head, padding, padding, padding: four references, three distinct.
        byte[] file = fileNode(
            new Cid[] { cHead, cPad, cPad, cPad },
            new int[] { head.length, padding.length, padding.length, padding.length });
        Cid cFile = dagCid(file);

        // What a dups=n gateway actually puts on the wire: each block once.
        byte[] car = car(cFile, new Block[] {
            new Block(cFile, file), new Block(cHead, head), new Block(cPad, padding),
        });

        File out = tmp("dedup");
        UnixFs.Stats st = UnixFs.extract(new ByteArrayInputStream(car), cFile, out);

        byte[] want = new byte[head.length + padding.length * 3];
        System.arraycopy(head, 0, want, 0, head.length);
        for (int i = 0; i < 3; i++) {
            System.arraycopy(padding, 0, want, head.length + i * padding.length, padding.length);
        }
        byte[] got = Files.readAllBytes(out.toPath());

        check("a repeated chunk is written once per reference, not once",
            java.util.Arrays.equals(want, got));
        check("the repeats are counted", st.duplicates == 2);
        check("only the distinct blocks were received", st.blocks == 3);
    }

    /**
     * Two identical files at opposite ends of a directory, with enough
     * distinct content between them that no memory-bounded window would
     * still hold the first copy when the second is referenced. The
     * ff8-texturepack-spells layer is exactly this: a block first served
     * at position 223 of 2235 is referenced again near the end, and a
     * 24 MiB LRU had evicted it, so the walk died on the next block as
     * "out of order" on every gateway alike. Repeats must be served from
     * where they were already written, whatever the distance.
     */
    private static void servesARepeatFromDiskHoweverFarApart() throws Exception {
        byte[] same = new byte[1024];
        java.util.Arrays.fill(same, (byte) 0x5a);
        Cid cSame = rawCid(same);

        // 64 distinct 1 MiB files in between: far more than any block cache
        // this walker ever had, and served once each like everything else.
        int between = 64;
        String[] names = new String[between + 2];
        Cid[] cids = new Cid[between + 2];
        int[] sizes = new int[between + 2];
        Block[] blocks = new Block[between + 2];
        names[0] = "a-first"; cids[0] = cSame; sizes[0] = same.length;
        blocks[1] = new Block(cSame, same);
        for (int i = 0; i < between; i++) {
            byte[] filler = new byte[1024 * 1024];
            java.util.Arrays.fill(filler, (byte) i);
            filler[0] = (byte) (i + 1);
            Cid c = rawCid(filler);
            names[i + 1] = "m-" + i; cids[i + 1] = c; sizes[i + 1] = filler.length;
            blocks[i + 2] = new Block(c, filler);
        }
        names[between + 1] = "z-last"; cids[between + 1] = cSame; sizes[between + 1] = same.length;
        byte[] dir = dirNode(names, cids, sizes);
        Cid cDir = dagCid(dir);
        blocks[0] = new Block(cDir, dir);

        File out = tmp("far");
        UnixFs.Stats st = UnixFs.extract(new ByteArrayInputStream(car(cDir, blocks)), cDir, out);

        check("the far repeat is written from the first copy",
            java.util.Arrays.equals(same, Files.readAllBytes(new File(out, "z-last").toPath())));
        check("the far repeat is counted", st.duplicates == 1);
        check("every distinct block was received once", st.blocks == between + 2);
    }

    private static void rejectsATamperedLeaf() throws Exception {
        byte[] content = "the quick brown fox".getBytes("UTF-8");
        Cid cid = rawCid(content);
        byte[] evil = content.clone();
        evil[0] ^= 0x01;

        // The CID still names the honest bytes; the block carries the lie.
        byte[] car = car(cid, new Block[] { new Block(cid, evil) });
        check("a flipped bit in a leaf is rejected", rejects(car, cid, "leaf"));
    }

    private static void rejectsATamperedInteriorNode() throws Exception {
        byte[] a = "alpha".getBytes("UTF-8");
        Cid ca = rawCid(a);
        byte[] dir = dirNode(new String[] { "a.txt" }, new Cid[] { ca }, new int[] { a.length });
        Cid cd = dagCid(dir);

        byte[] evilDir = dir.clone();
        evilDir[evilDir.length - 1] ^= 0x01;

        byte[] car = car(cd, new Block[] { new Block(cd, evilDir), new Block(ca, a) });
        check("a flipped bit in an interior node is rejected", rejects(car, cd, "interior"));
    }

    private static void rejectsATruncatedCar() throws Exception {
        byte[] a = "alpha".getBytes("UTF-8");
        Cid ca = rawCid(a);
        byte[] dir = dirNode(new String[] { "a.txt" }, new Cid[] { ca }, new int[] { a.length });
        Cid cd = dagCid(dir);
        byte[] car = car(cd, new Block[] { new Block(cd, dir), new Block(ca, a) });

        // Cut the promised child. A gateway that dies mid-stream must not
        // leave a half-written game looking complete.
        byte[] cut = java.util.Arrays.copyOf(car, car.length - (a.length + 8));
        check("a truncated CAR is rejected", rejects(cut, cd, "truncated"));
    }

    private static void rejectsARootThatWasNotRequested() throws Exception {
        byte[] content = "honest".getBytes("UTF-8");
        Cid cid = rawCid(content);
        byte[] car = car(cid, new Block[] { new Block(cid, content) });

        Cid wanted = rawCid("a completely different payload".getBytes("UTF-8"));
        check("a CAR rooted elsewhere is rejected", rejects(car, wanted, "wrong root"));
    }

    private static void cidTextRoundTrips() throws Exception {
        // The CIDv0 this repo pins for pokemon-blue.
        String v0 = "QmcYT8mZSfYRHz1D1QJRLiahgZP1GMLJAz43pVUouU6jq9";
        check("CIDv0 text round-trips", v0.equals(Cid.fromText(v0).toText()));

        Cid raw = rawCid("x".getBytes("UTF-8"));
        check("CIDv1 text round-trips", raw.equals(Cid.fromText(raw.toText())));
    }

    // ---- helpers ---------------------------------------------------------

    private static boolean rejects(byte[] car, Cid root, String what) {
        File out;
        try {
            out = tmp("reject-" + what);
        } catch (IOException e) {
            return false;
        }
        try {
            UnixFs.extract(new ByteArrayInputStream(car), root, out);
            return false; // accepting corrupt data is the failure
        } catch (VerifyException e) {
            return true;
        } catch (IOException e) {
            // A framing break that surfaces as a plain IOException is still
            // a refusal, which is the property under test.
            return true;
        }
    }

    private static void check(String what, boolean ok) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) {
            failures++;
        }
    }

    private static File tmp(String name) throws IOException {
        File d = Files.createTempDirectory("strom-test").toFile();
        return new File(d, name);
    }

    private static final class Block {
        final Cid cid;
        final byte[] data;

        Block(Cid cid, byte[] data) {
            this.cid = cid;
            this.data = data;
        }
    }

    private static byte[] sha256(byte[] b) throws Exception {
        return MessageDigest.getInstance("SHA-256").digest(b);
    }

    private static Cid rawCid(byte[] content) throws Exception {
        return new Cid(1, Cid.CODEC_RAW, sha256(content));
    }

    private static Cid dagCid(byte[] node) throws Exception {
        return new Cid(1, Cid.CODEC_DAG_PB, sha256(node));
    }

    /** A CARv1: varint-prefixed CBOR header, then varint-prefixed cid+block frames. */
    private static byte[] car(Cid root, Block[] blocks) throws IOException {
        ByteArrayOutputStream head = new ByteArrayOutputStream();
        head.write(0xa2);                                   // map(2)
        head.write(0x67);                                   // text(7)
        head.write("version".getBytes("UTF-8"));
        head.write(0x01);                                   // version: 1
        head.write(0x65);                                   // text(5)
        head.write("roots".getBytes("UTF-8"));
        head.write(0x81);                                   // array(1)
        byte[] rb = root.toBytes();
        head.write(0xd8);
        head.write(0x2a);                                   // tag(42)
        writeCborBytes(head, prefixIdentity(rb));

        ByteArrayOutputStream out = new ByteArrayOutputStream();
        writeVarint(out, head.size());
        out.write(head.toByteArray());
        for (Block b : blocks) {
            byte[] cid = b.cid.toBytes();
            writeVarint(out, cid.length + b.data.length);
            out.write(cid);
            out.write(b.data);
        }
        return out.toByteArray();
    }

    /** CBOR byte strings for a CID carry a leading 0x00 multibase identity prefix. */
    private static byte[] prefixIdentity(byte[] cid) {
        byte[] out = new byte[cid.length + 1];
        System.arraycopy(cid, 0, out, 1, cid.length);
        return out;
    }

    private static void writeCborBytes(ByteArrayOutputStream o, byte[] b) {
        if (b.length < 24) {
            o.write(0x40 | b.length);
        } else {
            o.write(0x58);
            o.write(b.length);
        }
        o.write(b, 0, b.length);
    }

    private static void writeVarint(ByteArrayOutputStream o, long v) {
        while (v >= 0x80) {
            o.write((int) ((v & 0x7f) | 0x80));
            v >>>= 7;
        }
        o.write((int) v);
    }

    /** A UnixFS chunked-file PBNode: links plus Data{type=file, filesize, blocksizes}. */
    private static byte[] fileNode(Cid[] cids, int[] sizes) throws IOException {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        long total = 0;
        for (int i = 0; i < cids.length; i++) {
            ByteArrayOutputStream link = new ByteArrayOutputStream();
            byte[] h = cids[i].toBytes();
            link.write(0x0a);
            writeVarint(link, h.length);
            link.write(h);
            link.write(0x12);                                // Name, empty for file chunks
            writeVarint(link, 0);
            link.write(0x18);
            writeVarint(link, sizes[i]);
            o.write(0x12);
            writeVarint(o, link.size());
            o.write(link.toByteArray());
            total += sizes[i];
        }
        ByteArrayOutputStream u = new ByteArrayOutputStream();
        u.write(0x08);
        writeVarint(u, 2);                                   // Type = file
        u.write(0x18);
        writeVarint(u, total);                               // filesize
        for (int s2 : sizes) {
            u.write(0x20);                                   // repeated blocksizes
            writeVarint(u, s2);
        }
        byte[] unixfs = u.toByteArray();
        o.write(0x0a);
        writeVarint(o, unixfs.length);
        o.write(unixfs);
        return o.toByteArray();
    }

    /** A UnixFS directory PBNode: links plus a Data field of type dir. */
    private static byte[] dirNode(String[] names, Cid[] cids, int[] sizes) throws IOException {
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        for (int i = 0; i < names.length; i++) {
            ByteArrayOutputStream link = new ByteArrayOutputStream();
            byte[] h = cids[i].toBytes();
            link.write(0x0a);                                // field 1, Hash
            writeVarint(link, h.length);
            link.write(h);
            byte[] n = names[i].getBytes("UTF-8");
            link.write(0x12);                                // field 2, Name
            writeVarint(link, n.length);
            link.write(n);
            link.write(0x18);                                // field 3, Tsize
            writeVarint(link, sizes[i]);

            o.write(0x12);                                   // PBNode field 2, Links
            writeVarint(o, link.size());
            o.write(link.toByteArray());
        }
        // PBNode field 1, Data = UnixFS{ Type: dir }
        byte[] unixfs = new byte[] { 0x08, 0x01 };
        o.write(0x0a);
        writeVarint(o, unixfs.length);
        o.write(unixfs);
        return o.toByteArray();
    }
}
