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
# busybox switch_root refuses to run without a regular file at /init. Booted
# by ABL, the vendor ramdisk brings Android's /init (and replaces this);
# booted through UEFI, our initramfs is the only one.
ln -s nx809j-init "$STAGE/init"
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
