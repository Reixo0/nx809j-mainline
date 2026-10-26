#!/usr/bin/env bash
# Install everything NX809J-specific into a root filesystem of any systemd
# distribution (mounted at <rootfs>, run as root):
#
#   device/rootfs/   services, rmtfs drop-in, udev rules, UCM, ... (as is)
#   firmware         scripts/firmware-files.sh -> /usr/lib/firmware
#   modules          out/modules (scripts/build.sh modules), unless MODULES=0
#   rmtfs copies     RMTFS_FROM=<dir>: the modem's file system copies from an
#                    old root (its /var/lib/rmtfs), so the modem keeps its state.
#                    Without it nx809j-rmtfs-copies.service makes fresh copies
#                    from the partitions on first boot.
#
# The distribution packages listed in device/README.md must be installed
# first, so that the presets can enable their services.
#
# Usage: sudo [MODULES=0] [RMTFS_FROM=dir] scripts/install-device-files.sh <rootfs>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:?usage: $0 <rootfs>}
[[ -d $DEST/usr && -d $DEST/etc ]] || { echo "$DEST does not look like a root filesystem" >&2; exit 1; }

# Files from device/rootfs, keeping their modes, owned by root
tar -C "$ROOT/device/rootfs" --owner=0 --group=0 -cf - . | tar -C "$DEST" --no-same-owner -xf -
echo "device files: $(find "$ROOT/device/rootfs" -type f | wc -l)"

# Firmware (the list script fails, and stops us, if a source is missing)
list=$("$ROOT"/scripts/firmware-files.sh)
n=0
while IFS= read -r pair; do
  f=${pair%%:*} src=${pair#*:}
  [[ -f $src ]] || { echo "missing $src" >&2; exit 1; }
  install -Dm644 "$src" "$DEST/usr/lib/firmware/$f"
  n=$((n + 1))
done <<< "$list"
echo "firmware files: $n"

if [[ ${MODULES:-1} == 1 ]]; then
  REL=$(cat "$ROOT/out/kernel/include/config/kernel.release")
  SRC=$ROOT/out/modules/lib/modules/$REL
  [[ -d $SRC ]] || { echo "no modules for $REL; run scripts/build.sh modules" >&2; exit 1; }
  rm -rf "$DEST/usr/lib/modules/$REL"
  mkdir -p "$DEST/usr/lib/modules"
  cp -a "$SRC" "$DEST/usr/lib/modules/"
  depmod -b "$DEST/usr" "$REL" 2>/dev/null || depmod -b "$DEST" "$REL"
  echo "modules: $REL"
fi

if [[ -n ${RMTFS_FROM:-} ]]; then
  for f in modem_fs1 modem_fs2 modem_fsc modem_fsg; do
    [[ -f $RMTFS_FROM/$f ]] || { echo "missing $RMTFS_FROM/$f" >&2; exit 1; }
  done
  install -d -m700 "$DEST/var/lib/rmtfs"
  install -m600 "$RMTFS_FROM"/modem_fs{1,2,c,g} "$DEST/var/lib/rmtfs/"
  echo "rmtfs copies from $RMTFS_FROM"
fi

# Enable what our preset names (services of packages that aren't installed
# are skipped with a warning)
units=$(awk '$1 == "enable" { print $2 }' "$ROOT"/device/rootfs/usr/lib/systemd/system-preset/*.preset)
systemctl --root="$DEST" preset $units || true
