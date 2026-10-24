#!/usr/bin/env python3
"""Turn a logical partition inside super into kernel cmdline arguments that
map it with dm-init (CONFIG_DM_INIT), e.g. for the linux_root partition.

Input is the start of super (its first 1 MiB holds the LP metadata), read
from the phone with:  sudo dd if=/dev/sda7 bs=4096 count=256

Usage: super-dm-cmdline.py <super-head.bin> [partition] [super block device]
Prints: dm-mod.create="..." dm-mod.waitfor=<dev>
"""
import struct
import sys

LP_GEOMETRY_MAGIC = 0x616c4467
LP_HEADER_MAGIC = 0x414c5030
LP_TARGET_TYPE_LINEAR = 0


def main():
    data = open(sys.argv[1], "rb").read()
    want = sys.argv[2] if len(sys.argv) > 2 else "linux_root"
    dev = sys.argv[3] if len(sys.argv) > 3 else "/dev/sda7"

    if struct.unpack_from("<I", data, 4096)[0] != LP_GEOMETRY_MAGIC:
        sys.exit("no LP geometry at 4096: not the start of super?")
    # Metadata slot 0 (primary) follows the primary and backup geometry
    h = data[4096 * 3:]
    magic, _maj, _min, hsize = struct.unpack_from("<IHHI", h, 0)
    if magic != LP_HEADER_MAGIC:
        sys.exit("no LP metadata header")
    off = 4 + 2 + 2 + 4 + 32
    tables_size, = struct.unpack_from("<I", h, off)
    off += 4 + 32
    desc = {}
    for name in ("partitions", "extents", "groups", "block_devices"):
        desc[name] = struct.unpack_from("<III", h, off)
        off += 12
    t = h[hsize:hsize + tables_size]

    def entries(name):
        o, n, sz = desc[name]
        return [t[o + i * sz:o + (i + 1) * sz] for i in range(n)]

    extents = [struct.unpack_from("<QIQI", e, 0) for e in entries("extents")]
    for e in entries("partitions"):
        name = e[:36].split(b"\0")[0].decode()
        if name != want:
            continue
        _attr, first, num, _grp = struct.unpack_from("<IIII", e, 36)
        table, logical = [], 0
        for num_sectors, target_type, target_data, target_source in extents[first:first + num]:
            if target_type != LP_TARGET_TYPE_LINEAR or target_source != 0:
                sys.exit(f"{want}: unsupported extent (type {target_type}, source {target_source})")
            # <start> <length> linear <device> <offset>, all in 512-byte sectors
            table.append(f"{logical} {num_sectors} linear {dev} {target_data}")
            logical += num_sectors
        if not table:
            sys.exit(f"{want} has no extents (zero size?)")
        print(f'dm-mod.create="{want},,,rw,{",".join(table)}" dm-mod.waitfor={dev}')
        print(f"# {want}: {logical * 512 / 2**30:.2f} GiB in {len(table)} extent(s)", file=sys.stderr)
        return
    sys.exit(f"no partition named {want} in super")


main()
