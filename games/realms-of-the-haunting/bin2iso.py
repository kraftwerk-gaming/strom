#!/usr/bin/env python3
"""Strip a MODE1/2352 raw CD .bin into a 2048-byte/sector ISO9660 image.

Each MODE1 sector is 2352 bytes: 12-byte sync + 4-byte header + 2048-byte
user data + 288-byte EDC/ECC. We keep only the 2048-byte payload (offset
16..2064) of every sector across the entire .bin so ISO9660 file extents
that live in a second data track still resolve.
"""

import sys


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f, open(dst, "wb") as o:
        while True:
            sec = f.read(2352)
            if len(sec) < 2352:
                break
            o.write(sec[16 : 16 + 2048])


if __name__ == "__main__":
    main()
