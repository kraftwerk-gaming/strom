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
