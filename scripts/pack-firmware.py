#!/usr/bin/env python3
"""Collect NX809J firmware from dump/ into the layout mainline expects.

Split .mdt/.bNN images are squashed into single .mbn files (same as
linux-msm/pil-squasher). Output: out/firmware/lib/firmware/qcom/...

Usage: pack-firmware.py [dump_dir] [out_dir]
"""
import shutil, struct, subprocess, sys, os
from pathlib import Path

root = Path(__file__).resolve().parent.parent
dump = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "dump"
out = (Path(sys.argv[2]) if len(sys.argv) > 2 else root / "out/firmware") / "lib/firmware/qcom"
dev = out / "kaanapali/nubia/nx809j"
img = dump / "firmware/vendor_firmware_mnt/image"
vfw = dump / "firmware/vendor_firmware"


def squash(mdt: Path, dst: Path):
    """Rebuild a full ELF from <name>.mdt (headers) + <name>.bNN (segments)."""
    data = bytearray(mdt.read_bytes())
    if data[:4] != b"\x7fELF":
        raise ValueError(f"{mdt} is not an ELF")
    is64 = data[4] == 2
    if is64:
        phoff, = struct.unpack_from("<Q", data, 0x20)
        phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
    else:
        phoff, = struct.unpack_from("<I", data, 0x1c)
        phentsize, phnum = struct.unpack_from("<HH", data, 0x2a)
    for i in range(phnum):
        ph = phoff + i * phentsize
        if is64:
            p_offset, = struct.unpack_from("<Q", data, ph + 8)
            p_filesz, = struct.unpack_from("<Q", data, ph + 32)
        else:
            p_offset, = struct.unpack_from("<I", data, ph + 4)
            p_filesz, = struct.unpack_from("<I", data, ph + 16)
        if not p_filesz:
            continue
        seg = mdt.with_suffix(f".b{i:02d}")
        if not seg.exists():
            continue  # segment 0/1 (headers, hash) are already inside the .mdt
        blob = seg.read_bytes()
        end = p_offset + len(blob)
        if len(data) < end:
            data.extend(b"\0" * (end - len(data)))
        data[p_offset:end] = blob
    dst.write_bytes(data)


def main():
    dev.mkdir(parents=True, exist_ok=True)
    for name in ["adsp", "adsp_dtb", "cdsp", "cdsp_dtb", "modem", "modem_dtb", "ipa_fws"]:
        mdt = img / f"{name}.mdt"
        if mdt.exists():
            squash(mdt, dev / f"{name}.mbn")
            print(f"squashed {name}.mbn")
        else:
            print(f"missing  {name}.mdt")

    # SoCCP lives in its own FAT partition
    soccp = dump / "partitions/soccp_a.img"
    if soccp.exists():
        env = dict(os.environ, MTOOLS_SKIP_CHECK="1")
        for f in ["soccp.mbn", "soccp_dtb.mbn"]:
            subprocess.run(["mcopy", "-n", "-o", "-i", str(soccp), f"::/image/{f}", str(dev / f)],
                           check=True, env=env)
            print(f"copied   {f}")

    # Adreno 840: generic microcode in qcom/, signed zap shader per device
    for f in ["gen80200_sqe.fw", "gen80200_gmu.bin", "gen80200_aqe.fw"]:
        shutil.copy2(vfw / f, out / f)
    shutil.copy2(vfw / "gen80200_zap.mbn", dev / "gen80200_zap.mbn")
    print("copied   gpu firmware")
    print(f"-> {out}")


main()
