#!/usr/bin/env python3
"""Extract the Mode 2 profile (GM2P, 120 bytes) from a gbl-chainload efisp
image (its GBLP1 container, entry type 0x0010), so Canoe can keep the
exact identity Android's KeyMint data is bound to.

Usage: extract-gm2p.py efisp.img boot.gm2p
"""
import hashlib, struct, sys, zlib

d = open(sys.argv[1], "rb").read()
i = 0
while (i := d.find(b"GBLP1\0\0\0", i)) >= 0:
    ver, hsize, flags, total, count, crc = struct.unpack_from("<HHIIII", d, i + 8)
    if ver == 1 and hsize == 28 and zlib.crc32(d[i:i + 24]) == crc:
        c = d[i:i + total]
        for e in range(count):
            typ, _, off, size, _, sha = struct.unpack_from("<HHIII32s", c, 28 + 48 * e)
            p = c[off:off + size]
            if typ == 0x10 and size == 120 and p[:4] == b"GM2P":
                if hashlib.sha256(p).digest() != sha:
                    sys.exit("profile checksum mismatch")
                open(sys.argv[2], "wb").write(p)
                v, spl = struct.unpack_from("<II", p, 16)
                print("profile: os_version 0x%x spl 0x%x pubkey %s"
                      % (v, spl, p[56:88].hex()))
                sys.exit(0)
    i += 1
sys.exit("no GBLP1 Mode 2 profile found")
