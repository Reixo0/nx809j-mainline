#!/usr/bin/env bash
# Turn pmbootstrap's root image into one the phone can boot over NBD:
#  - copy it out of pmbootstrap's work dir (root-owned there; qemu-nbd runs
#    as the user and needs write access)
#  - grow it (default 8G) so packages can be installed
#  - make the /boot fstab entry nofail: the phone boots via boot_a and the
#    shim, so the pmOS boot partition never shows up and systemd would
#    otherwise go to emergency mode
#
#  - put the first user (uid 10000) in the video, render, input and audio
#    groups (pmbootstrap didn't for the console UI; DRM and input need them)
#  - install ~/.ssh/id_ed25519.pub as that user's authorized_keys
#  - with DEV_SUDO=1: passwordless sudo for that user (dev rootfs only; it
#    lives on the PC and SSH is key-only over the USB link)
#
# Usage: [DEV_SUDO=1] scripts/pmos-prepare-root.sh [size]   (after pmbootstrap install --split)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIZE=${1:-8G}
WORK=$(pmbootstrap config work 2>/dev/null || echo "$HOME/.local/var/pmbootstrap")
SRC=$WORK/chroot_native/home/pmos/rootfs/nubia-nx809j-root.img
IMG=${IMG:-$ROOT/out/pmos/nubia-nx809j-root.img}
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
# Replace a file inside the image (owner root), keeping things simple for debugfs
put() {   # put <local file> <image path> <octal mode>
  debugfs -w -R "rm $2" "$IMG" >/dev/null 2>&1 || true
  debugfs -w -R "write $1 $2" "$IMG" >/dev/null 2>&1
  debugfs -w -R "sif $2 mode 0100$3" "$IMG" >/dev/null 2>&1
}

USER_NAME=$(debugfs -R 'cat /etc/passwd' "$IMG" 2>/dev/null | awk -F: '$3 == 10000 {print $1}')
if [[ -n $USER_NAME ]]; then
  debugfs -R 'cat /etc/group' "$IMG" 2>/dev/null > "$TMP.group"
  for g in video render input audio; do
    # add USER_NAME to the member list of group g if it isn't there yet
    awk -F: -v OFS=: -v g="$g" -v u="$USER_NAME" '
      $1 == g { n = split($4, m, ","); found = 0
                for (i = 1; i <= n; i++) if (m[i] == u) found = 1
                if (!found) $4 = ($4 == "" ? u : $4 "," u) }
      { print }' "$TMP.group" > "$TMP.group.new" && mv "$TMP.group.new" "$TMP.group"
  done
  put "$TMP.group" /etc/group 644
  echo "groups for $USER_NAME: $(grep -E '^(video|render|input|audio):' "$TMP.group" | cut -d: -f1 | tr '\n' ' ')"
  if [[ ${DEV_SUDO:-0} == 1 ]]; then
    echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > "$TMP.sudoers"
    put "$TMP.sudoers" /etc/sudoers.d/90-nx809j-dev 440
    echo "passwordless sudo for $USER_NAME (DEV_SUDO=1)"
  fi
  KEY=$HOME/.ssh/id_ed25519.pub
  if [[ -f $KEY ]]; then
    H=$(debugfs -R 'cat /etc/passwd' "$IMG" 2>/dev/null | awk -F: '$3 == 10000 {print $6}')
    debugfs -w -R "mkdir $H/.ssh" "$IMG" >/dev/null 2>&1 || true
    put "$KEY" "$H/.ssh/authorized_keys" 600
    for p in "$H/.ssh" "$H/.ssh/authorized_keys"; do
      debugfs -w -R "sif $p uid 10000" "$IMG" >/dev/null 2>&1
      debugfs -w -R "sif $p gid 10000" "$IMG" >/dev/null 2>&1
    done
    debugfs -w -R "sif $H/.ssh mode 040700" "$IMG" >/dev/null 2>&1
    echo "ssh key installed for $USER_NAME"
  fi
  rm -f "$TMP.group" "$TMP.sudoers"
fi

e2fsck -fn "$IMG" | tail -1
echo "ready: $IMG (now run scripts/pmos-add-firmware.sh)"
