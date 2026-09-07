package gaming.kraftwerk.strom.ipfs;

/**
 * The bundle entry-name rule. The archive's bytes are verified by CID
 * before they reach the extractor, so this rule is the only thing between
 * an archive's idea of a path and the game directory it may not leave.
 * The decoding itself is libarchive's and needs a device; the rule is
 * pure string logic and runs here.
 */
public final class BundleTest {
    private static int failures = 0;

    public static void main(String[] args) {
        theTarPrefixIsStripped();
        theRootMapsToTheDirectoryItself();
        parentReferencesAreRefusedAnywhere();
        absoluteNamesAreRefused();
        oddButHarmlessNamesAreNormalised();

        if (failures > 0) {
            System.err.println(failures + " test(s) failed");
            System.exit(1);
        }
        System.out.println("all bundle tests passed");
    }

    private static void theTarPrefixIsStripped() {
        check("./CARS/foo.bin -> CARS/foo.bin",
            "CARS/foo.bin".equals(Bundle.relative("./CARS/foo.bin")));
        check("a directory entry keeps its name without the slash",
            "CARS".equals(Bundle.relative("./CARS/")));
        check("a name with no prefix is itself",
            "a/b/c".equals(Bundle.relative("a/b/c")));
    }

    private static void theRootMapsToTheDirectoryItself() {
        check("./ is the root", "".equals(Bundle.relative("./")));
        check(". is the root", "".equals(Bundle.relative(".")));
        check("an empty name is refused", Bundle.relative("") == null);
    }

    private static void parentReferencesAreRefusedAnywhere() {
        check("../x", Bundle.relative("../x") == null);
        check("./../x", Bundle.relative("./../x") == null);
        check("a/../../x", Bundle.relative("a/../../x") == null);
        check("a/b/..", Bundle.relative("a/b/..") == null);
        // Would resolve inside the tree, but a bundle we made never
        // contains one, and refusing is cheaper than being clever.
        check("a/../b is refused too", Bundle.relative("a/../b") == null);
        check("a component that merely starts with dots is a name",
            "..a/...b".equals(Bundle.relative("..a/...b")));
    }

    private static void absoluteNamesAreRefused() {
        check("/etc/passwd", Bundle.relative("/etc/passwd") == null);
        check("/", Bundle.relative("/") == null);
        check("//x", Bundle.relative("//x") == null);
    }

    private static void oddButHarmlessNamesAreNormalised() {
        check("doubled slashes collapse", "a/b".equals(Bundle.relative("a//b")));
        check("inner dots vanish", "a/b".equals(Bundle.relative("a/./b/.")));
        check("a trailing slash vanishes", "a/b".equals(Bundle.relative("a/b/")));
    }

    private static void check(String what, boolean ok) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) {
            failures++;
        }
    }
}
