{ stdenv }:

stdenv.mkDerivation {
  name = "subreaper";
  dontUnpack = true;
  buildPhase = ''
    cat > subreaper.c << 'EOF'
    #include <sys/prctl.h>
    #include <unistd.h>
    #include <stdio.h>

    /* Set PR_SET_CHILD_SUBREAPER then exec the given command.
       Orphaned descendants get reparented to this process instead
       of init, so kill/wait can reach them. */
    int main(int argc, char **argv) {
        if (argc < 2) {
            fprintf(stderr, "usage: subreaper cmd [args...]\n");
            return 1;
        }
        if (prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0) {
            perror("prctl(PR_SET_CHILD_SUBREAPER)");
            return 1;
        }
        execvp(argv[1], argv + 1);
        perror("exec");
        return 1;
    }
    EOF
    $CC -O2 -o subreaper subreaper.c
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp subreaper $out/bin/
  '';
}
