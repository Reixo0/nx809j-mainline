#!/usr/bin/env python3
"""Patch the NX809J's vendor UEFI drivers for Mu-Silicium.

Usage: patch-dxe.py <extracted-dir>

<extracted-dir> is the output of tools/fv-extract.py (one directory per
driver). Each patched driver is written next to the original as
<name>.patched.efi. Every patch checks the bytes it replaces, so a different
firmware build fails loudly instead of being patched in the wrong place.

The patches are the OnePlus 15 (infiniti) ones from Project-Silicium's
Device-Binaries, located again in the NX809J build
(BOOT.MXF.2.5.3-00131-KAANAPALI-1.124266.24). From infiniti's OnePlus-only
patches, the PmicDxe battery presence read is needed here too; its dead
battery check and the QcomChargerDxe patch are not: that code does not
exist in this build.
"""
import os
import struct
import sys


def b(src, dst, link=False):
    """AArch64 B/BL from src to dst."""
    off = (dst - src) >> 2
    assert -(1 << 25) <= off < (1 << 25)
    return struct.pack('<I', (0x94000000 if link else 0x14000000) | (off & 0x3ffffff))


def cbnz_w(rt, src, dst):
    off = (dst - src) >> 2
    return struct.pack('<I', 0x35000000 | ((off & 0x7ffff) << 5) | rt)


def insn(*words):
    return b''.join(struct.pack('<I', w) for w in words)


NOP = insn(0xd503201f)
RET_0 = insn(0x2a1f03e0, 0xd65f03c0)        # mov w0, wzr; ret
MOV_W8_WZR = insn(0x2a1f03e8)
MOV_W1_WZR = insn(0x2a1f03e1)
MOV_X1_1 = insn(0xd2800021)
MOV_X0_X19 = insn(0xaa1303e0)


def ufs_extra():
    """Code for UFSDxe's new .extra section at 0x27000.

    Wakes the UFS link (LinkWake(hba, 0)) before the call at 0x13dbc that
    Qualcomm's code makes on a link that the boot loader left asleep. On
    failure it returns to the original error check with the error in w0
    (the infiniti version loops forever there).
    """
    base = 0x27000
    code = MOV_W1_WZR                                   # 27000
    code += b(base + 0x04, 0x12b8c, link=True)          # bl LinkWake
    code += cbnz_w(0, base + 0x08, base + 0x14)         # cbnz w0, out
    code += MOV_X0_X19                                  # mov x0, x19
    code += b(base + 0x10, 0x13738, link=True)          # bl original callee
    code += b(base + 0x14, 0x13dc0)                     # out: b back
    return code.ljust(0x1000, b'\0')


# PE header of UFSDxe with the fourth section (.extra, RX, VA/raw 0x27000,
# size 0x1000): NumberOfSections 4, SizeOfCode and SizeOfImage grown by
# 0x1000, plus the section table entry.
UFS_HEADER = [
    (0xe5c, insn(0x0003aa64), insn(0x0004aa64)),
    (0xea8, insn(0x00027000), insn(0x00028000)),
    (0xfd8, bytes(40), b'.extra\0\0' + struct.pack('<IIII', 0x1000, 0x27000, 0x1000, 0x27000)
     + bytes(12) + struct.pack('<I', 0x60000020)),
]

PATCHES = {
    # Power key: the special Qualcomm key code 0x102 becomes Enter (0xd).
    'ButtonsDxe': [
        (0x3810, insn(0x52802048), insn(0x528001a8)),   # mov w8, #0xd
        (0x3814, insn(0x17ffffe8), b(0x3814, 0x383c)),  # store as UnicodeChar
    ],
    # Minimal PMIC init crashes; the PMIC is already set up by XBL.
    'PmicDxe': [
        (0x419c, insn(0x9400645b), NOP),
        (0x41a4, insn(0x94005e88), NOP),
        (0x41ac, insn(0x94003f1a), NOP),
        # Logs the SDAM boot error code, then reads PMIC 1 SID 0xc register
        # 0x4454 (battery presence). After ABL that SPMI channel is not
        # ours: synchronous external abort. Same as infiniti's 0x2768c.
        (0x1d27c, bytes.fromhex('fd7bbea9f30b00f9'), RET_0),
    ],
    # SPMI PIC init (pairs with the PmicDxe patch).
    'SPMI': [
        (0x2ea0, bytes.fromhex('fd7bbda9f65701a9'), RET_0),
    ],
    # Global "TZ applets loaded" flag set to TRUE.
    'TzDxeLA': [
        (0xf5f0, b'\0', b'\1'),
    ],
    # UFS: wake instead of sleep, and wake the link.
    'UFSDxe': UFS_HEADER + [
        (0xc450, insn(0x94000664, 0x35fffd80), MOV_X1_1 + b(0xc454, 0xdf00, link=True)),
        (0x12ba0, insn(0x3952a408), MOV_W8_WZR),
        (0x13dbc, insn(0x97fffe5f), b(0x13dbc, 0x27000)),
    ],
    # Keep the IOMMU attached at ExitBootServices so USB keeps working.
    'UsbConfigDxe': [
        (0x4e1c, insn(0x34000128), b(0x4e1c, 0x4e40)),
    ],
    # Mass storage: report the disk as non-removable.
    'UsbMsdDxe': [
        (0x3f74, insn(0x52801008), MOV_W8_WZR),
    ],
}


def patch(name, data):
    data = bytearray(data)
    for off, old, new in PATCHES[name]:
        assert len(old) == len(new), (name, hex(off))
        if data[off:off + len(old)] != old:
            raise SystemExit(f'{name}: unexpected bytes at {off:#x}: '
                             f'{data[off:off + len(old)].hex()} != {old.hex()}')
        data[off:off + len(new)] = new
    if name == 'UFSDxe':
        if len(data) != 0x27000:
            raise SystemExit('UFSDxe: unexpected size')
        data += ufs_extra()
    return bytes(data)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    top = sys.argv[1]
    for name in PATCHES:
        src = os.path.join(top, name, name + '.efi')
        out = os.path.join(top, name, name + '.patched.efi')
        open(out, 'wb').write(patch(name, open(src, 'rb').read()))
        print(f'patched {name}')


if __name__ == '__main__':
    main()
