#!/usr/bin/env bash
# Build the Arch Linux ARM release images for the NX809J on an aarch64 Arch
# Linux ARM host (the phone itself works), as root:
#
#   linux.img   root file system for the `linux` partition: Denial, its apps,
#               our [nx809j] packages; grows to the partition on first boot
#   esp.img     the `esp` partition: systemd-boot, kernel and DTB, the
#               dispatcher (EFI/BOOT/BOOTAA64.EFI) and Mu-Silicium (MU.fd)
#
# No phone firmware is included: firmware/nx809j-firmware.sh adds it from
# Android after flashing.
#
# Usage: sudo REPO=file:///path/to/repo DISPATCH=dispatch.efi MUFD=MU.fd \
#          scripts/make-arch-image.sh [outdir]
#   REPO       where pacman finds [nx809j] while building (default: the
#              GitHub release the image itself is configured with)
#   USERNAME, PASSWORD   the phone's user (default alarm / 147147)
set -euo pipefail
OUT=$(realpath "${1:-.}")
RELEASE_REPO=https://github.com/Reixo0/nx809j-mainline/releases/download/arch-repo
REPO=${REPO:-$RELEASE_REPO}
: "${DISPATCH:?DISPATCH=dispatch.efi (uefi/mu-silicium-nx809j/esp-dispatch)}"
: "${MUFD:?MUFD=MU.fd (esp-dispatch/extract-mu-fd.py)}"
USERNAME=${USERNAME:-alarm}
PASSWORD=${PASSWORD:-147147}
ROOT_SIZE=${ROOT_SIZE:-12G}
ESP_SIZE=1G # the esp partition

PACKAGES=(base archlinuxarm-keyring sudo nano nx809j-device
  # Denial, its services and apps
  denial-nx809j phonewave-nx809j denial-apps-nx809j xdg-desktop-portal-gtk
  xdg-user-dirs foot firefox mobile-config-firefox
  # Hardware
  mesa vulkan-freedreno pipewire pipewire-pulse wireplumber alsa-utils
  bluez power-profiles-daemon dosfstools openssh)
SERVICES=(NetworkManager bluetooth nx809j-denial power-profiles-daemon
  systemd-resolved systemd-timesyncd)

[[ $(uname -m) == aarch64 && $(id -u) == 0 ]] || { echo "run as root on aarch64" >&2; exit 1; }
command -v pacstrap >/dev/null || { echo "needs arch-install-scripts" >&2; exit 1; }

work=$(mktemp -d /var/tmp/nx809j-image.XXXXXX)
M=$work/root
cleanup() {
  umount -R "$M" 2>/dev/null || true
  # Never delete through a mount: the image (or worse) may still be on $M
  if mountpoint -q "$M" || mountpoint -q "$M/boot"; then
    echo "$M is still mounted, leaving $work" >&2
  else
    rm -rf --one-file-system "$work"
  fi
}
trap cleanup EXIT

rm -f "$OUT/linux.img" "$OUT/esp.img"
truncate -s "$ROOT_SIZE" "$OUT/linux.img"
mkfs.ext4 -q -L linux "$OUT/linux.img"
truncate -s "$ESP_SIZE" "$OUT/esp.img"
# UFS has 4096-byte sectors: FAT has to use them too
mkfs.fat -F 32 -S 4096 -n ESP "$OUT/esp.img" >/dev/null
mkdir -p "$M"
mount -o loop "$OUT/linux.img" "$M"
mkdir -p "$M/boot"
mount -o loop,umask=0077 "$OUT/esp.img" "$M/boot"

# The host's repositories plus [nx809j]
conf=$work/pacman.conf
sed '/^\[nx809j\]/,/^$/d' /etc/pacman.conf > "$conf"
printf '\n[nx809j]\nSigLevel = Optional TrustAll\nServer = %s\n' "$REPO" >> "$conf"
pacstrap -C "$conf" -K "$M" "${PACKAGES[@]}"

# The image's own pacman.conf gets [nx809j] from the GitHub release
sed -i '/^\[nx809j\]/,/^$/d' "$M/etc/pacman.conf"
printf '\n[nx809j]\nSigLevel = Optional TrustAll\nServer = %s\n' "$RELEASE_REPO" >> "$M/etc/pacman.conf"

cat > "$M/etc/fstab" <<'EOF'
# <file system>	<dir>	<type>	<options>	<dump>	<pass>
PARTLABEL=linux	/	ext4	rw,relatime,x-systemd.growfs	0 1
PARTLABEL=esp	/boot	vfat	rw,relatime,umask=0077,nofail	0 2
EOF
echo nx809j > "$M/etc/hostname"
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' "$M/etc/locale.gen"
echo LANG=en_US.UTF-8 > "$M/etc/locale.conf"
ln -sf /usr/share/zoneinfo/UTC "$M/etc/localtime"
ln -sf /run/systemd/resolve/stub-resolv.conf "$M/etc/resolv.conf"

# The user, who Denial runs as; sudo for wheel; "Reboot to Linux" works
# without a password
mkdir -p "$M/etc/sudoers.d" "$M/etc/systemd/system/nx809j-denial.service.d"
printf '[Service]\nUser=%s\nGroup=%s\n' "$USERNAME" "$USERNAME" \
  > "$M/etc/systemd/system/nx809j-denial.service.d/10-user.conf"
cat > "$M/etc/sudoers.d/10-nx809j" <<'EOF'
%wheel ALL=(ALL:ALL) ALL
%wheel ALL=(root) NOPASSWD: /usr/bin/nx809j-reboot-linux
EOF
chmod 440 "$M/etc/sudoers.d/10-nx809j"

arch-chroot "$M" /bin/bash -e <<EOF
locale-gen >/dev/null
pacman-key --populate archlinuxarm >/dev/null
useradd -m -G wheel,audio,video,input,network,rfkill "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
passwd -l root >/dev/null
systemctl enable ${SERVICES[*]}
bootctl install --no-variables --esp-path=/boot >/dev/null
gpgconf --homedir /etc/pacman.d/gnupg --kill all
EOF

# Boot chain on the ESP: the dispatcher starts Mu-Silicium when the
# Qualcomm UEFI runs it, and systemd-boot (EFI/systemd) under Mu
install -m644 "$DISPATCH" "$M/boot/EFI/BOOT/BOOTAA64.EFI"
install -Dm644 "$MUFD" "$M/boot/nx809j/mu/MU.fd"
cat > "$M/boot/loader/loader.conf" <<'EOF'
default nx809j.conf
timeout 3
console-mode keep
editor no
EOF

# Nothing machine specific in the image
rm -rf "$M"/var/cache/pacman/pkg/* "$M"/var/log/journal/* "$M/boot/loader/random-seed"
: > "$M/etc/machine-id"

# Give anything the chroot started a moment to let go of the mount
for i in 1 2 3 4 5; do umount -R "$M" 2>/dev/null && break; sleep 2; done
mountpoint -q "$M" && { echo "can't unmount $M" >&2; exit 1; }
e2fsck -fy "$OUT/linux.img" >/dev/null || true
resize2fs -M "$OUT/linux.img" >/dev/null 2>&1
blocks=$(dumpe2fs -h "$OUT/linux.img" 2>/dev/null | awk -F: '/^Block count/ { print $2 }')
truncate -s $((blocks * 4096)) "$OUT/linux.img"
ls -l "$OUT/linux.img" "$OUT/esp.img"
