#!/usr/bin/env python3
"""Extract the drivers from a UEFI firmware volume (FV) dump.

Usage: fv-extract.py <fv.bin> <outdir>

Writes <outdir>/<UI name>/{<name>.efi,<name>.depex,<name>.guid} for every
FFS file with a PE32 section, recursing into nested FV_IMAGE sections.
Accepts a whole Qualcomm uefi.img (ELF): the first firmware volume found is
parsed, and LZMA-compressed sections inside it are unpacked.
"""
import lzma
import os
import struct
import sys
import uuid

FFS_ATTRIB_LARGE_FILE = 0x01
SECTION_PE32, SECTION_TE, SECTION_DXE_DEPEX = 0x10, 0x12, 0x13
SECTION_UI, SECTION_FV_IMAGE, SECTION_GUID_DEFINED = 0x15, 0x17, 0x02
SECTION_RAW = 0x19
LZMA_GUID = 'EE4E5898-3914-4259-9D6E-DC7BD79403CF'
FILE_TYPES = {0x07: 'DRIVER', 0x09: 'APPLICATION', 0x05: 'DXE_CORE',
              0x0b: 'FV_IMAGE', 0x02: 'FREEFORM', 0x01: 'RAW',
              0x06: 'PEIM', 0x04: 'PEI_CORE', 0x0a: 'SMM'}


def guid(b):
    return str(uuid.UUID(bytes_le=bytes(b))).upper()


def align(x, a):
    return (x + a - 1) & ~(a - 1)


def sections(data, off, end):
    """Yield (type, body) for the sections in data[off:end], unpacking
    LZMA-compressed GUID-defined sections in place."""
    while off + 4 <= end:
        size = int.from_bytes(data[off:off + 3], 'little')
        typ = data[off + 3]
        hdr = 4
        if size == 0xffffff:
            size = struct.unpack_from('<I', data, off + 4)[0]
            hdr = 8
        if size < hdr:
            break
        if typ == SECTION_GUID_DEFINED:
            sguid = guid(data[off + hdr:off + hdr + 16])
            doff = struct.unpack_from('<H', data, off + hdr + 16)[0]
            if sguid == LZMA_GUID:
                inner = lzma.decompress(data[off + doff:off + size],
                                        format=lzma.FORMAT_ALONE)
                yield from sections(inner, 0, len(inner))
            else:
                print(f'GUID-defined section {sguid} not handled',
                      file=sys.stderr)
        else:
            yield typ, data[off + hdr:off + size]
        off = align(off + size, 4)


def parse_fv(data, out, files):
    if data[0x28:0x2c] != b'_FVH':
        # volume inside a larger image (ELF, or a section header in front)
        i = data.find(b'_FVH')
        if i < 0x28:
            raise SystemExit('no firmware volume found')
        data = data[i - 0x28:]
    fv_len = struct.unpack_from('<Q', data, 0x20)[0]
    hdr_len = struct.unpack_from('<H', data, 0x30)[0]
    ext_off = struct.unpack_from('<H', data, 0x34)[0]
    off = hdr_len
    if ext_off:
        off = ext_off + struct.unpack_from('<I', data, ext_off + 16)[0]
    off = align(off, 8)
    while off + 24 <= min(fv_len, len(data)):
        name = data[off:off + 16]
        if data[off:off + 24] == b'\xff' * 24:  # free space
            break
        ftype = data[off + 18]
        attr = data[off + 19]
        size = int.from_bytes(data[off + 20:off + 23], 'little')
        hdr = 24
        if attr & FFS_ATTRIB_LARGE_FILE:
            size = struct.unpack_from('<Q', data, off + 24)[0]
            hdr = 32
        if ftype != 0xf0:  # skip pad files
            handle_file(data, off + hdr, off + size, guid(name), ftype,
                        out, files)
        off = align(off + size, 8)


def handle_file(data, off, end, fguid, ftype, out, files):
    ui = pe = depex = None
    for typ, body in sections(data, off, end):
        if typ == SECTION_UI:
            ui = body.decode('utf-16-le').rstrip('\0')
        elif typ in (SECTION_PE32, SECTION_TE):
            pe = body
        elif typ == SECTION_DXE_DEPEX:
            depex = body
        elif typ == SECTION_FV_IMAGE:
            parse_fv(body, out, files)
    name = ui or fguid
    if pe is None and ftype not in (0x01, 0x02):
        return
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    if pe is not None:
        open(os.path.join(d, name + '.efi'), 'wb').write(pe)
    elif ftype in (0x01, 0x02):
        for typ, body in sections(data, off, end):
            if typ == SECTION_RAW:
                open(os.path.join(d, name), 'wb').write(body)
    if depex is not None:
        open(os.path.join(d, name + '.depex'), 'wb').write(depex)
    open(os.path.join(d, name + '.guid'), 'w').write(
        f'{fguid} {FILE_TYPES.get(ftype, hex(ftype))}\n')
    files.append((name, fguid, FILE_TYPES.get(ftype, hex(ftype)),
                  pe is not None, depex is not None))


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    data = open(sys.argv[1], 'rb').read()
    files = []
    parse_fv(data, sys.argv[2], files)
    for name, fguid, ftype, has_pe, has_depex in files:
        print(f'{ftype:12} {fguid} {name}'
              f'{"" if has_pe else " (no PE)"}{" +depex" if has_depex else ""}')


if __name__ == '__main__':
    main()
