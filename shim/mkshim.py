#!/usr/bin/env python3
"""Lay out shim + mainline DTB + Linux Image as one arm64 Image (see layout.h).

Usage: mkshim.py <shim.bin> <mainline.dtb> <linux Image> <out Image>
"""
import struct
import sys
from pathlib import Path

# Keep in sync with layout.h
CODE_MAX, DTB_OFF, OUT_OFF, KERNEL_OFF = 0x10000, 0x20000, 0x100000, 0x200000
ARM64_MAGIC = b"ARM\x64"


def main():
    shim, dtb, kernel = (Path(p).read_bytes() for p in sys.argv[1:4])
    out = Path(sys.argv[4])

    if len(shim) > CODE_MAX:
        sys.exit(f"shim is {len(shim)} bytes, max {CODE_MAX}")
    if dtb[:4] != b"\xd0\x0d\xfe\xed":
        sys.exit("mainline DTB has no FDT magic")
    if DTB_OFF + len(dtb) > OUT_OFF:
        sys.exit(f"DTB is {len(dtb)} bytes, max {OUT_OFF - DTB_OFF}")
    if kernel[56:60] != ARM64_MAGIC:
        sys.exit("kernel is not an uncompressed arm64 Image")

    text_offset, image_size, flags = struct.unpack_from("<QQQ", kernel, 8)
    if text_offset != 0:
        sys.exit(f"kernel text_offset is {text_offset:#x}, expected 0")

    img = bytearray(KERNEL_OFF)
    img[:len(shim)] = shim
    img[DTB_OFF:DTB_OFF + len(dtb)] = dtb
    img += kernel
    # Shim header: cover the whole kernel incl. its BSS, same placement flags
    struct.pack_into("<QQ", img, 16, KERNEL_OFF + image_size, flags)
    out.write_bytes(img)
    print(f"{out}: shim {len(shim)} B, dtb {len(dtb)} B, kernel image_size "
          f"{image_size:#x}, total image_size {KERNEL_OFF + image_size:#x}")


main()
