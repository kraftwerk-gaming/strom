# pkgs/gamenative-redirect/default.nix
#
# The LD_PRELOAD path shim for strom's GameNative build, replacing the
# closed-source libredirect.so upstream ships.
#
# GameNative runs wine under box64 on a Winlator imagefs whose every
# binary was built with /data/data/com.winlator/files/imagefs baked in:
# libxcb's X socket path, fontconfig's font dirs, the X11 locale tables,
# hundreds of RUNPATHs. An app cannot create /data/data/com.winlator, so
# something has to rewrite those paths at runtime, and upstream does it
# with a preload they keep closed ("all rights reserved", no
# redistribution grant -- see their THIRD_PARTY_NOTICES). Our release of
# a GameNative fork cannot carry that blob, so this is the same job done
# with nixpkgs' MIT-licensed libredirect (`NIX_REDIRECTS=/from=/to:...`),
# vendored with the wrappers wine reaches those paths through that the
# nixpkgs copy lacks (dlopen, lstat, readlink, realpath, the fortified
# open entry points). The fork's launcher preloads it and sets
# NIX_REDIRECTS to the imagefs it actually installed into.
#
# Cross-built for aarch64 glibc: the preload sits in the glibc process
# tree (ld-linux-aarch64 -> box64 -> wine), not in the bionic app, so
# no NDK is involved. The imagefs glibc is 2.41; the symbol versions
# this ends up needing are checked below so a newer nixpkgs glibc cannot
# silently produce a library the phone's loader rejects.
#
# Output: a tarball shaped like upstream's redirect.tzst asset
# (usr/lib/<lib>), dropped into the fork as app/src/main/assets, plus
# the bare .so for inspection.
{
  lib,
  pkgsCross,
  stdenvNoCC,
  patchelf,
  zstd,
  gnutar,
}:
let
  cross = pkgsCross.aarch64-multiplatform;
  shim = cross.stdenv.mkDerivation {
    pname = "libstromredirect";
    version = "1";
    src = ./libredirect.c;
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      $CC -Wall -std=c99 -O2 -fPIC -shared -o libstromredirect.so $src
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm644 libstromredirect.so $out/lib/libstromredirect.so
      runHook postInstall
    '';
    # The link wraps in a RUNPATH to the cross glibc's store path; on the
    # phone that is a dead entry the loader skips, but it has no business
    # in the artifact.
    postFixup = ''
      patchelf --remove-rpath $out/lib/libstromredirect.so
    '';
    nativeBuildInputs = [ patchelf ];
    meta = {
      description = "Path-rewriting LD_PRELOAD for GameNative's Winlator imagefs";
      license = lib.licenses.mit;
      platforms = [ "aarch64-linux" ];
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "gamenative-redirect";
  version = shim.version;
  dontUnpack = true;
  nativeBuildInputs = [
    zstd
    gnutar
    cross.stdenv.cc.bintools.bintools
  ];
  buildPhase = ''
    runHook preBuild
    # The imagefs ships glibc 2.41. Refuse a build that needs newer
    # symbol versions than that, since it would only fail on the phone.
    newest=$(${cross.stdenv.cc.bintools.targetPrefix}readelf --dyn-syms ${shim}/lib/libstromredirect.so \
      | grep -oE 'GLIBC_2\.[0-9]+' | sort -uV | tail -1)
    echo "newest glibc symbol version needed: $newest"
    if [ "$(printf '%s\n%s\n' "$newest" GLIBC_2.41 | sort -V | tail -1)" != GLIBC_2.41 ]; then
      echo "libstromredirect.so needs $newest, newer than the imagefs glibc 2.41" >&2
      exit 1
    fi
    mkdir -p tree/usr/lib
    cp ${shim}/lib/libstromredirect.so tree/usr/lib/
    chmod 755 tree/usr/lib/libstromredirect.so
    tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='1970-01-01' \
      -C tree -cf - usr | zstd -19 -o redirect.tzst
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp redirect.tzst $out/
    cp ${shim}/lib/libstromredirect.so $out/
    runHook postInstall
  '';
  passthru = { inherit shim; };
  meta = shim.meta // {
    platforms = lib.platforms.linux;
  };
}
