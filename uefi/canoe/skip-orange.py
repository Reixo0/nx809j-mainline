#!/usr/bin/env python3
"""Make a prepared Canoe loader (boot.efi from canoe-image build, NX809J ABL
built 2026-03-20) skip the orange "boot loader is unlocked" screen.

In Mode 2 the ABL still sees the unlocked device, so its verified-boot
screen code shows the orange warning (and waits) before booting. Canoe's
own patch for that screen only knows the OnePlus ABL. Here, after the
"Boot State is : %d" debug print, BootState 1 (ORANGE) branches to the
warning; point that branch at the code after the switch instead.
Android still gets green/locked from the Mode 2 rewrite.

Usage: skip-orange.py boot.efi out.efi
"""
import struct, sys

SITE, WARN, AFTER = 0x149D4, 0x14A30, 0x14A54  # file offsets == RVAs


def b_eq(src, dst):
    return 0x54000000 | (((dst - src) >> 2) & 0x7FFFF) << 5


d = bytearray(open(sys.argv[1], "rb").read())
cur, = struct.unpack_from("<I", d, SITE)
# cmp w8, #1 just before the branch
if struct.unpack_from("<I", d, SITE - 4)[0] != 0x7100051F or cur != b_eq(SITE, WARN):
    sys.exit("unexpected code at 0x%x: not the ABL this patch was made for" % SITE)
struct.pack_into("<I", d, SITE, b_eq(SITE, AFTER))
open(sys.argv[2], "wb").write(d)
print("patched b.eq at 0x%x -> 0x%x" % (SITE, AFTER))
