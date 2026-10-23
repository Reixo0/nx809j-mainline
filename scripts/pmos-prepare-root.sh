#!/usr/bin/env bash
# Turn pmbootstrap's root image into one the phone can boot over NBD:
#  - copy it out of pmbootstrap's work dir (root-owned there; qemu-nbd runs
#    as the user and needs write access)
#  - grow it (default 8G) so packages can be installed
#  - make the /boot fstab entry nofail: the phone boots via boot_a and the
#    shim, so the pmOS boot partition never shows up and systemd would
#    otherwise go to emergency mode
#
# Usage: scripts/pmos-prepare-root.sh [size]     (after pmbootstrap install --split)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIZE=${1:-8G}
WORK=$(pmbootstrap config work 2>/dev/null || echo "$HOME/.local/var/pmbootstrap")
SRC=$WORK/chroot_native/home/pmos/rootfs/nubia-nx809j-root.img
IMG=$ROOT/out/pmos/nubia-nx809j-root.img
TMP=$ROOT/out/pmos/fstab

[[ -f $SRC ]] || { echo "no $SRC (run: pmbootstrap install --split)" >&2; exit 1; }
if [[ -f $IMG ]]; then
  read -rp "$IMG exists (any changes made on the phone are in it). Overwrite? [y/N] " a
  [[ $a == [yY] ]] || exit 1
fi
mkdir -p "$(dirname "$IMG")"
cp --sparse=always "$SRC" "$IMG"
truncate -s "$SIZE" "$IMG"
e2fsck -fy "$IMG" >/dev/null || [[ $? -le 1 ]]
resize2fs "$IMG" >/dev/null

debugfs -R 'cat /etc/fstab' "$IMG" 2>/dev/null > "$TMP"
sed -i -E 's|^(UUID=[0-9a-f-]+ /boot [a-z0-9]+ )([^ ]+)( .*)$|\1\2,nofail,x-systemd.device-timeout=1s\3|' "$TMP"
grep -q 'nofail' "$TMP" || { echo "couldn't patch the /boot fstab line:" >&2; cat "$TMP" >&2; exit 1; }
debugfs -w -R 'rm /etc/fstab' "$IMG" >/dev/null 2>&1
debugfs -w -R "write $TMP /etc/fstab" "$IMG" >/dev/null 2>&1
e2fsck -fn "$IMG" | tail -1
echo "ready: $IMG"
