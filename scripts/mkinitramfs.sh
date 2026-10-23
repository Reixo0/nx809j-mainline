#!/usr/bin/env bash
# Stage the bring-up initramfs and write it as an uncompressed cpio:
#   out/initramfs.cpio  -> built into the kernel (CONFIG_INITRAMFS_SOURCE)
#
# Built in rather than (only) passed as a boot.img ramdisk: ABL appends the
# boot.img ramdisk after the stock vendor_boot one, and on this phone our
# files went missing after unpacking (no error logged). The built-in
# initramfs is unpacked first, so /nx809j-init exists regardless.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUSYBOX=$ROOT/tools/dl/busybox/bin/busybox.static
STAGE=$ROOT/out/initramfs

rm -rf "$STAGE"; mkdir -p "$STAGE/nx809j"
install -m755 "$BUSYBOX" "$STAGE/nx809j/busybox"
install -m755 "$ROOT/initramfs/init" "$STAGE/nx809j-init"
# Firmware for the remoteprocs we start (scripts/pack-firmware.py output).
# Kept to what's enabled: it's built into the kernel image.
FW_SRC=$ROOT/out/firmware/lib/firmware
FW_FILES=${FW_FILES:-"qcom/kaanapali/nubia/nx809j/adsp.mbn qcom/kaanapali/nubia/nx809j/adsp_dtb.mbn
  qcom/kaanapali/nubia/nx809j/soccp.mbn qcom/kaanapali/nubia/nx809j/soccp_dtb.mbn"}
for f in $FW_FILES; do
  [[ -f $FW_SRC/$f ]] || { echo "missing $FW_SRC/$f (run scripts/pack-firmware.py)" >&2; exit 1; }
  install -D -m644 "$FW_SRC/$f" "$STAGE/lib/firmware/$f"
done
# defconfig modules are ~100MB+; only pack them when asked (INCLUDE_MODULES=1)
if [[ ${INCLUDE_MODULES:-0} == 1 && -d $ROOT/out/modules/lib/modules ]]; then
  mkdir -p "$STAGE/lib"; cp -a "$ROOT/out/modules/lib/modules" "$STAGE/lib/"
fi
# Only rewrite when the contents change, so the kernel isn't relinked for nothing
(cd "$STAGE" && find . | LC_ALL=C sort | cpio -o -H newc --quiet --reproducible) > "$ROOT/out/initramfs.cpio.new"
if cmp -s "$ROOT/out/initramfs.cpio.new" "$ROOT/out/initramfs.cpio"; then
  rm "$ROOT/out/initramfs.cpio.new"
else
  mv "$ROOT/out/initramfs.cpio.new" "$ROOT/out/initramfs.cpio"
fi
