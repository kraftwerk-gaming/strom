#!/usr/bin/env python3
"""Enumerate a UnixFS directory DAG through HTTP gateways.

Every public gateway answers `?format=car&dag-scope=block` for a path
(the one block that path resolves to, as a CARv1) and serves a file
inside a directory as plain bytes with Range support. Nothing else is
universal -- `?format=dag-json` and `?format=tar` each work on some
gateways and 406 on others -- so this is the whole protocol: fetch
directory blocks one at a time, decode them here, and hand the file
list to aria2c, which downloads each file by path the way fetch-ipfs
already downloads a single-file CID.

Output, one entry per line, tab separated:

    d\t<path>                         a directory (so empty ones get created)
    f\t<size>\t<x>\t<quoted>\t<path>  a file; size in bytes, x = 1 if
                                     executable, quoted = the path
                                     percent-encoded for a gateway URL

Paths are relative to the root and unescaped in the last column; a name
containing a tab or newline aborts, because the output could not carry it.

Verification is not this script's job: the derivation's recursive
outputHash covers every byte of the tree, so a gateway serving wrong
blocks fails the build the same way a wrong single file does today.
"""

import base64
import os
import ssl
from concurrent.futures import ThreadPoolExecutor
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CODEC_RAW = 0x55
CODEC_DAG_PB = 0x70

UNIXFS_DIRECTORY = 1
UNIXFS_FILE = 2
UNIXFS_SYMLINK = 4
UNIXFS_HAMT = 5

MAX_BLOCK = 4 << 20  # one block is at most 2 MiB; a CAR of one block a bit more


class WalkError(Exception):
    pass


# ---- protobuf / CAR primitives ------------------------------------------


def varint(buf, i):
    shift = 0
    n = 0
    while True:
        if i >= len(buf):
            raise WalkError("truncated varint")
        b = buf[i]
        i += 1
        n |= (b & 0x7F) << shift
        if not b & 0x80:
            return n, i
        shift += 7
        if shift > 63:
            raise WalkError("varint too long")


def fields(buf):
    """Yield (field number, wire type, value) for one protobuf message."""
    i = 0
    while i < len(buf):
        key, i = varint(buf, i)
        f, wt = key >> 3, key & 7
        if wt == 0:
            v, i = varint(buf, i)
        elif wt == 2:
            n, i = varint(buf, i)
            v = buf[i : i + n]
            if len(v) != n:
                raise WalkError("truncated field")
            i += n
        elif wt == 1:
            v = buf[i : i + 8]
            i += 8
        elif wt == 5:
            v = buf[i : i + 4]
            i += 4
        else:
            raise WalkError("unsupported wire type %d" % wt)
        yield f, wt, v


def read_cid(buf, i):
    """Return (codec, cid bytes, next index) for the CID starting at i."""
    start = i
    if buf[i] == 0x12 and buf[i + 1] == 0x20:
        return CODEC_DAG_PB, bytes(buf[i : i + 34]), i + 34
    version, i = varint(buf, i)
    if version != 1:
        raise WalkError("unsupported CID version %d" % version)
    codec, i = varint(buf, i)
    _code, i = varint(buf, i)
    n, i = varint(buf, i)
    i += n
    return codec, bytes(buf[start:i]), i


def cid_text(cid):
    if cid[0] == 0x12:
        return b58(cid)
    return "b" + base64.b32encode(cid).decode().lower().rstrip("=")


def parse_cid(text):
    if text.startswith("Qm"):
        n = 0
        for ch in text:
            n = n * 58 + B58.index(ch)
        return n.to_bytes(34, "big")
    if not text.startswith("b"):
        raise WalkError("unsupported CID multibase: %s" % text)
    body = text[1:].upper()
    body += "=" * (-len(body) % 8)
    return base64.b32decode(body)


B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def b58(raw):
    n = int.from_bytes(raw, "big")
    out = ""
    while n:
        n, r = divmod(n, 58)
        out = B58[r] + out
    pad = len(raw) - len(raw.lstrip(b"\0"))
    return "1" * pad + out


def car_blocks(car):
    """Every block of a CARv1: (codec, cid bytes, data)."""
    hlen, i = varint(car, 0)
    header = car[i : i + hlen]
    i += hlen
    # The header is CBOR {version: 1, roots: [...]}; version 1 is the
    # only one gateways emit. Match the encoded key to avoid a decoder.
    if b"version\x01" not in header:
        raise WalkError("not a CARv1")
    while i < len(car):
        n, i = varint(car, i)
        end = i + n
        codec, cid, i = read_cid(car, i)
        yield codec, cid, bytes(car[i:end])
        i = end


def decode_pb_node(data):
    """dag-pb: (links [(name, codec, cid, tsize)], unixfs data bytes)."""
    links = []
    payload = b""
    for f, wt, v in fields(data):
        if f == 2 and wt == 2:
            name, cid, codec, tsize = "", None, None, 0
            for lf, lwt, lv in fields(v):
                if lf == 1 and lwt == 2:
                    codec, cid, _ = read_cid(lv, 0)
                elif lf == 2 and lwt == 2:
                    name = lv.decode("utf-8")
                elif lf == 3 and lwt == 0:
                    tsize = lv
            if cid is None:
                raise WalkError("link without a CID")
            links.append((name, codec, cid, tsize))
        elif f == 1 and wt == 2:
            payload = v
    return links, payload


def decode_unixfs(payload):
    """UnixFS Data: (type, filesize, mode)."""
    kind, size, mode = None, 0, 0
    for f, wt, v in fields(payload):
        if f == 1 and wt == 0:
            kind = v
        elif f == 3 and wt == 0:
            size = v
        elif f == 7 and wt == 0:
            mode = v
    if kind is None:
        raise WalkError("dag-pb node without a UnixFS type")
    return kind, size, mode


# ---- gateway access ------------------------------------------------------


class Gateways:
    def __init__(self, gateways):
        self.gateways = gateways
        self.rounds = 3
        # Inside a Nix build there is no system trust store; the
        # derivation names the bundle in SSL_CERT_FILE the way curl reads it.
        bundle = os.environ.get("SSL_CERT_FILE")
        self.ctx = ssl.create_default_context(cafile=bundle) if bundle else None

    def block(self, ref, want):
        """Fetch the block with CID `want` that a gateway path resolves to.

        A CAR for a path carries the blocks along the path first (the
        root, each directory) and the target last, so the target is
        picked by its CID, which the parent's link already named."""
        last = None
        for attempt in range(self.rounds):
            for gw in self.gateways:
                url = "%s/ipfs/%s?format=car&dag-scope=block" % (gw, ref)
                req = urllib.request.Request(
                    url,
                    headers={
                        "Accept": "application/vnd.ipld.car",
                        "User-Agent": "curl/8",
                    },
                )
                try:
                    with urllib.request.urlopen(req, timeout=90, context=self.ctx) as r:
                        car = r.read(MAX_BLOCK + 1)
                    if len(car) > MAX_BLOCK:
                        raise WalkError("CAR larger than %d bytes" % MAX_BLOCK)
                    for codec, cid, data in car_blocks(car):
                        if cid == want:
                            return codec, data
                    raise WalkError(
                        "CAR for %s lacks the block %s" % (ref, cid_text(want))
                    )
                except (urllib.error.URLError, OSError, WalkError) as e:
                    last = e
                    log("%s: %s" % (gw, e))
            if attempt + 1 < self.rounds:
                time.sleep(10)
        raise WalkError("no gateway served %s: %s" % (ref, last))


def log(msg):
    sys.stderr.write("[ipfs-walk] %s\n" % msg)
    sys.stderr.flush()


# ---- the walk ------------------------------------------------------------


def quote(path):
    return "/".join(urllib.parse.quote(p, safe="") for p in path.split("/"))


def classify(gw, root, path, name, lcodec, lcid, tsize):
    """One entry of a directory: ("f", size, x, child) or ("d", child, ref)."""
    child = name if path == "" else path + "/" + name
    childref = root + "/" + quote(child)
    if lcodec == CODEC_RAW:
        # A raw leaf is a whole small file; the link's size is its byte count.
        return ("f", tsize, 0, child)
    if lcodec != CODEC_DAG_PB:
        raise WalkError("%s: unsupported codec 0x%x" % (child, lcodec))
    ccodec, cdata = gw.block(childref, lcid)
    if ccodec != CODEC_DAG_PB:
        raise WalkError("%s: gateway returned a different codec" % child)
    _links, cpayload = decode_pb_node(cdata)
    ckind, csize, cmode = decode_unixfs(cpayload)
    if ckind == UNIXFS_FILE:
        return ("f", csize, 1 if cmode & 0o111 else 0, child)
    if ckind in (UNIXFS_DIRECTORY, UNIXFS_HAMT):
        return ("d", child, childref, lcid)
    if ckind == UNIXFS_SYMLINK:
        raise WalkError("%s: symlinks are not supported in a fetched tree" % child)
    raise WalkError("%s: unsupported UnixFS type %d" % (child, ckind))


def walk(gw, root, root_cid, out, pool):
    """Directory by directory; the entries of one directory are looked up
    in parallel, since each chunked file costs a gateway round trip."""
    # Each pending item: (path relative to root, gateway ref) where the
    # ref is a path under the root for anything a gateway can address by
    # name, and a bare CID for a HAMT sub-shard, which has no name.
    pending = [("", root, root_cid)]
    count = 0
    while pending:
        path, ref, cid = pending.pop()
        codec, data = gw.block(ref, cid)
        if codec != CODEC_DAG_PB:
            raise WalkError("%s: expected a directory node" % (path or "/"))
        links, payload = decode_pb_node(data)
        kind, _, _ = decode_unixfs(payload)
        if kind == UNIXFS_DIRECTORY:
            entries = links
        elif kind == UNIXFS_HAMT:
            entries = []
            for name, lcodec, lcid, tsize in links:
                # A shard link is 2 hex chars of bucket prefix, then the
                # entry name; a bare prefix is a sub-shard.
                if len(name) == 2:
                    pending.append((path, cid_text(lcid), lcid))
                else:
                    entries.append((name[2:], lcodec, lcid, tsize))
        else:
            raise WalkError(
                "%s: not a directory (UnixFS type %d)" % (path or "/", kind)
            )

        for name, _, _, _ in entries:
            if (
                not name
                or "/" in name
                or "\t" in name
                or "\n" in name
                or name in (".", "..")
            ):
                raise WalkError("unusable entry name %r under %s" % (name, path or "/"))
        jobs = [
            pool.submit(classify, gw, root, path, name, lcodec, lcid, tsize)
            for name, lcodec, lcid, tsize in entries
        ]
        for job in jobs:
            r = job.result()
            if r[0] == "f":
                out.write("f\t%d\t%d\t%s\t%s\n" % (r[1], r[2], quote(r[3]), r[3]))
                count += 1
            else:
                out.write("d\t%s\n" % r[1])
                pending.append((r[1], r[2], r[3]))
        log("%s: %d entries, %d files so far" % (path or "/", len(entries), count))
    return count


def main():
    if len(sys.argv) < 4:
        sys.stderr.write("usage: ipfs-walk.py <cid> <listing-out> <gateway>...\n")
        sys.exit(2)
    root = sys.argv[1]
    listing = sys.argv[2]
    gateways = [g.rstrip("/") for g in sys.argv[3:]]
    gw = Gateways(gateways)
    with open(listing, "w") as out, ThreadPoolExecutor(max_workers=16) as pool:
        n = walk(gw, root, parse_cid(root), out, pool)
    log("%s: %d files" % (root, n))


if __name__ == "__main__":
    try:
        main()
    except WalkError as e:
        log("error: %s" % e)
        sys.exit(1)
