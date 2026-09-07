# strom-bundle: turn a game's built tree into its pinned bundle.
#
#   nix run .#bundle -- <slug> <pin-url>
#
# Builds `androidPayloads.<slug>` (the tree the desktop overlay presents
# at default settings), packs it as ONE reproducible tar.zst, uploads it
# to the pin endpoint (the anonymous tar-upload service: POST a tar,
# get the pinned directory's CID back), and prints the `fetchIpfs {
# bundle = true; }` block for the recipe with the bundle's own file CID,
# sha256 and size.
#
# Reproducible by construction: entries sorted, owner 0:0, mtime epoch,
# modes normalised (the store's 0444/0555 become 0644/0755), hard links
# dereferenced (an optimised store hard-links identical files, and tar
# would otherwise emit link entries on that machine and full files on
# another), and zstd at fixed parameters. The same tree packs to the
# same bytes on any machine running this flake (zstd's output is a
# function of its version and parameters, and nixpkgs pins the
# version). `-19 --long=27` is the measured sweet spot: LZMA-class ratio
# (70% of the tree for a game of pre-compressed assets, within 1% of
# 7z/xz) at zstd's decode speed, which sits on the disk-write floor. 27
# is also the largest window zstd decoders accept by default, which is
# what libarchive's filter and `tar --zstd` do; do not raise it.
#
# The bundle's file CID is computed locally (`ipfs add --only-hash
# --cid-version=1`, the same add the endpoint runs recursively over the
# uploaded directory), so the CID printed here is fetchable at
# /ipfs/<cid> as soon as the upload is pinned; the directory CID the
# endpoint answers with is the pin's GC root, worth keeping in the
# commit message for `ipfs-roots rm` later.
#
# No pin host is named here on purpose: pass it, like STROM_IPFS_GATEWAYS
# on the fetch side keeps private infrastructure out of the repo.
{ pkgs }:

pkgs.writeShellApplication {
  name = "strom-bundle";
  runtimeInputs = with pkgs; [
    nix
    gnutar
    zstd
    kubo
    curl
    jq
    coreutils
  ];
  text = ''
        if [[ $# -ne 2 ]]; then
          echo "usage: strom-bundle <slug> <pin-url>" >&2
          exit 1
        fi
        slug=$1
        pin=''${2%/}
        flake=''${STROM_FLAKE:-.}

        echo "[bundle] building $flake#androidPayloads.$slug" >&2
        tree=$(nix build --no-link --print-out-paths "$flake#androidPayloads.$slug")

        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        out="$work/$slug.tar.zst"

        echo "[bundle] packing $tree" >&2
        tar --sort=name --owner=0 --group=0 --numeric-owner --hard-dereference \
          --mtime='1970-01-01 00:00:00 UTC' --mode='u+rw,go+r' \
          -c -C "$tree" . \
          | zstd -19 --long=27 -T0 -q -o "$out"

        size=$(stat -c %s "$out")
        hash=$(nix hash file --sri "$out")
        export IPFS_PATH="$work/ipfs"
        ipfs init -e >/dev/null 2>&1
        cid=$(ipfs add -Q --only-hash --cid-version=1 "$out")
        echo "[bundle] $size bytes, $hash, $cid" >&2

        echo "[bundle] uploading to $pin/" >&2
        reply=$(tar -c -C "$work" "$slug.tar.zst" \
          | curl -sS --fail-with-body --max-time 7200 --data-binary @- "$pin/")
        root=$(jq -r .cid <<<"$reply")
        echo "[bundle] pinned; GC root (directory) $root" >&2

        # The endpoint's gateway, when it has one at the same host: a quick
        # sanity check that the file CID resolves. Advisory only; the fetch
        # side races the public pool as well.
        if curl -fsSI --max-time 60 "$pin/ipfs/$cid?filename=x.bin&download=true" >/dev/null 2>&1; then
          echo "[bundle] $pin/ipfs/$cid serves the bundle" >&2
        else
          echo "[bundle] note: $pin/ipfs/$cid did not answer a HEAD; not necessarily a problem" >&2
        fi

        cat <<EOF

      src = fetchIpfs {
        cid = "$cid";
        bundle = true;
        hash = "$hash";
        name = "$slug.tar.zst";
        size = $size;
      };
    EOF
  '';
}
