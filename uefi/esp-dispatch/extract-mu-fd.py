#!/usr/bin/env python3
"""Extract the raw 3 MiB Mu-Silicium FD from a boot image built by
uefi/build.sh, for the ESP dispatcher (\\nx809j\\mu\\MU.fd).

The boot image's kernel is a gzip of BootShim + FD (+ appended DTB). The
shim's first instruction is "adr x1, _Payload", which gives the FD offset.

Usage: extract-mu-fd.py out/Mu-nx809j.img out/mu-esp/MU.fd
"""
import struct, sys, zlib

FD_SIZE = 0x300000

img = open(sys.argv[1], "rb").read()
if img[:8] != b"ANDROID!":
    sys.exit("not an Android boot image")
kernel_size, = struct.unpack_from("<I", img, 8)
page = 4096  # header v3/v4
d = zlib.decompressobj(16 + zlib.MAX_WBITS)
kernel = d.decompress(img[page:page + kernel_size])
insn, = struct.unpack_from("<I", kernel, 0)
if insn & 0x9F000000 != 0x10000000 or insn & 0x1F != 1:
    sys.exit("shim does not start with adr x1 (0x%08x)" % insn)
imm = ((insn >> 5) & 0x7FFFF) << 2 | (insn >> 29) & 3
fd = kernel[imm:imm + FD_SIZE]
if len(fd) != FD_SIZE:
    sys.exit("FD truncated")
open(sys.argv[2], "wb").write(fd)
print("FD at 0x%x, %d bytes -> %s" % (imm, len(fd), sys.argv[2]))
