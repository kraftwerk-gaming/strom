#!/usr/bin/env python3
"""Emit the listing of a local tree in ipfs-walk.py's output format.

One line per entry, exactly what the walker would discover for the same
tree through the gateways:

    d\t<path>
    f\t<size>\t<x>\t<quoted>\t<path>

`x` is 1 for an executable file, `quoted` is the path with every
segment percent-encoded the way a gateway URL wants it (the same
`quote()` as ipfs-walk.py). Entries are sorted so the manifest is
reproducible; the consumer (lib/fetch-ipfs.nix) does not care about
order.

This is the sidecar manifest: generated from the built tree at pin
time and pinned beside it, so a client downloads one small file
instead of walking the DAG with one gateway request per entry --
public gateways rate-limit by request count, and the walk of a
2000-file game is ~2200 requests before the first payload byte
(measured: 419 responses of 429 across one such walk).

Trust: the manifest only *names* files; every consumer still verifies
content end to end (the desktop's NAR outputHash, the phone's
per-block CID checks), so a wrong manifest fails the fetch rather
than corrupting it.
"""

import os
import sys
import urllib.parse


def quote(path):
    return "/".join(urllib.parse.quote(p, safe="") for p in path.split("/"))


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: tree-manifest.py <tree>")
    root = sys.argv[1]
    lines = []

    def check(name, path):
        # The same names ipfs-walk.py refuses: a tab or newline would
        # corrupt this TSV, and a gateway path cannot address them.
        if "\t" in name or "\n" in name:
            sys.exit("tree-manifest: unusable entry name %r" % path)

    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        for name in dirnames:
            path = name if rel == "." else rel + "/" + name
            check(name, path)
            if os.path.islink(os.path.join(dirpath, name)):
                sys.exit("tree-manifest: symlink %s; a fetched tree has none" % path)
            lines.append("d\t%s" % path)
        for name in filenames:
            path = name if rel == "." else rel + "/" + name
            check(name, path)
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                sys.exit("tree-manifest: symlink %s; a fetched tree has none" % path)
            st = os.stat(full)
            x = 1 if st.st_mode & 0o111 else 0
            lines.append("f\t%d\t%d\t%s\t%s" % (st.st_size, x, quote(path), path))
    lines.sort()
    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
