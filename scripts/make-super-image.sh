#!/usr/bin/env bash
# Make a flashable image for the linux_root logical partition inside super
# from the NBD rootfs image (out/pmos/nubia-nx809j-root.img):
#   out/pmos/linux_root.img   raw, exactly SIZE
#   out/pmos/linux_root.simg  Android sparse (only used blocks go over USB)
#
# Flash from fastbootd (fastboot reboot fastboot):
#   fastboot create-logical-partition linux_root <SIZE in bytes>
#   fastboot flash linux_root out/pmos/linux_root.simg
#
# Usage: scripts/make-super-image.sh [size]     (default 9G; phone off, NBD stopped)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$ROOT/out/pmos/nubia-nx809j-root.img}
RAW=$ROOT/out/pmos/linux_root.img
SPARSE=$ROOT/out/pmos/linux_root.simg
SIZE=${1:-9G}

# exact path match: a pattern could also match other image names
if pgrep -a qemu-nbd | grep -qF -- "$SRC"; then
  echo "qemu-nbd is serving $SRC; power the phone off and stop it first" >&2
  exit 1
fi
bytes=$(numfmt --from=iec "$SIZE")

cp --sparse=always "$SRC" "$RAW"
# Replay the journal / repair, then shrink the filesystem to fit the partition
e2fsck -fy "$RAW" >/dev/null || [[ $? -le 1 ]]
resize2fs "$RAW" "$((bytes / 1024))K" >/dev/null
truncate -s "$bytes" "$RAW"
e2fsck -fn "$RAW" | tail -1

img2simg "$RAW" "$SPARSE"
echo "raw:    $RAW ($SIZE = $bytes bytes)"
echo "sparse: $SPARSE ($(du -h "$SPARSE" | cut -f1))"
echo "partition size for fastboot create-logical-partition: $bytes"
