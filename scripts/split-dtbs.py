#!/usr/bin/env python3
"""Split concatenated DTBs (vendor_boot dtb section, dtbo partition) and decompile them.
Usage: split-dtbs.py <blob> <outdir>"""
import struct, subprocess, sys, pathlib

blob = pathlib.Path(sys.argv[1]).read_bytes()
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
off = n = 0
while (off := blob.find(b"\xd0\x0d\xfe\xed", off)) != -1:
    size = struct.unpack(">I", blob[off + 4:off + 8])[0]
    if size < 64 or off + size > len(blob):
        off += 4; continue
    dtb = out / f"{n:02d}.dtb"
    dtb.write_bytes(blob[off:off + size])
    dts = dtb.with_suffix(".dts")
    subprocess.run(["dtc", "-q", "-I", "dtb", "-O", "dts", "-o", dts, dtb], check=False)
    head = dts.read_text(errors="replace") if dts.exists() else ""
    model = next((l.split("=", 1)[1].strip() for l in head.splitlines() if l.strip().startswith("model =")), "?")
    print(f"{dtb.name} off=0x{off:x} size={size} model={model}")
    off += size; n += 1
