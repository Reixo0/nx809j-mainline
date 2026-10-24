#!/usr/bin/env bash
# Install our phone firmware (GPU, ADSP, CDSP, SoCCP; not the modem) into the
# postmarketOS root image under /lib/firmware, offline, while nothing serves it.
# The GPU driver loads its firmware on first open, after switch_root, so it has
# to be in the rootfs and not only in the kernel's initramfs.
#
# Usage: scripts/pmos-add-firmware.sh [rootfs.img]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG=${1:-$ROOT/out/pmos/nubia-nx809j-root.img}
FW=$ROOT/out/firmware/lib/firmware
FILES="qcom/gen80200_sqe.fw qcom/gen80200_gmu.bin qcom/gen80200_aqe.fw
  qcom/kaanapali/nubia/nx809j/gen80200_zap.mbn
  qcom/kaanapali/nubia/nx809j/adsp.mbn qcom/kaanapali/nubia/nx809j/adsp_dtb.mbn
  qcom/kaanapali/nubia/nx809j/cdsp.mbn qcom/kaanapali/nubia/nx809j/cdsp_dtb.mbn
  qcom/kaanapali/nubia/nx809j/soccp.mbn qcom/kaanapali/nubia/nx809j/soccp_dtb.mbn"

# exact path match: a pattern could also match other image names
if pgrep -a qemu-nbd | grep -qF -- "$IMG"; then
  echo "qemu-nbd is serving $IMG; stop it (and keep the phone off) first" >&2
  exit 1
fi

# The phone's last session may have ended without unmounting: replay the
# journal before touching anything, or a later replay could undo our writes
e2fsck -fy "$IMG" >/dev/null || [[ $? -le 1 ]]

cmds=$(mktemp)
declare -A made=()
for f in $FILES; do
  src=$FW/$f
  # Same preference as scripts/mkinitramfs.sh: upstream linux-firmware first
  [[ -f $ROOT/tools/dl/linux-firmware/$f ]] && src=$ROOT/tools/dl/linux-firmware/$f
  [[ -f $src ]] || { echo "missing $src" >&2; exit 1; }
  d=/usr/lib/firmware
  for part in $(dirname "$f" | tr / ' '); do
    d=$d/$part
    [[ -n ${made[$d]:-} ]] || { echo "mkdir $d"; made[$d]=1; }
  done
  echo "rm /usr/lib/firmware/$f"
  echo "write $src /usr/lib/firmware/$f"
  echo "sif /usr/lib/firmware/$f mode 0100644"
done > "$cmds"
debugfs -w -f "$cmds" "$IMG" 2>&1 | grep -vE '^debugfs|^(mkdir|rm|write|sif) |Allocated inode|File not found by ext2_lookup|already exists' || true
rm -f "$cmds"

e2fsck -fn "$IMG" | tail -1
for f in $FILES; do
  printf '%-48s %s\n' "$f" "$(debugfs -R "stat /usr/lib/firmware/$f" "$IMG" 2>/dev/null | grep -oE 'Size: [0-9]+')"
done
