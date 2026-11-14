#!/usr/bin/env bash
# Build the Fedora release images for the NX809J on an aarch64 Fedora host
# (the phone itself works), as root. The counterpart of
# scripts/make-arch-image.sh:
#
#   linux.img   root file system for the `linux` partition: Denial, its apps,
#               our RPMs (fedora/rpm); grows to the partition on first boot
#   esp.img     the `esp` partition: systemd-boot, kernel and DTB, the
#               dispatcher (EFI/BOOT/BOOTAA64.EFI) and Mu-Silicium (MU.fd)
#
# No phone firmware is included: firmware/nx809j-firmware.sh adds it from
# Android after flashing. FIRMWARE=file.tar (the script's tar output) puts it in
# the image instead, for this phone only: such an image must never be published.
#
# Usage: sudo REPO=/path/to/repo DISPATCH=dispatch.efi MUFD=MU.fd \
#          scripts/make-fedora-image.sh [outdir]
#   REPO       our dnf repository while building (fedora/build-rpms.sh's
#              output; default: the published one the image is configured with)
#   RELEASEVER Fedora release (default: the host's)
#   USERNAME, PASSWORD   the phone's user (default alarm / 147147)
#   FIRMWARE   the phone's own firmware, see above
set -euo pipefail
OUT=$(realpath "${1:-.}")
# Where the image's dnf finds our packages. Not published yet: RELEASE.md
RELEASE_REPO=https://reixo0.github.io/nx809j-mainline/fedora/$(rpm -E %fedora)/aarch64
REPO=${REPO:-$RELEASE_REPO}
[[ $REPO == /* ]] && REPO=file://$REPO
: "${DISPATCH:?DISPATCH=dispatch.efi (uefi/mu-silicium-nx809j/esp-dispatch)}"
: "${MUFD:?MUFD=MU.fd (esp-dispatch/extract-mu-fd.py)}"
RELEASEVER=${RELEASEVER:-$(rpm -E %fedora)}
USERNAME=${USERNAME:-alarm}
PASSWORD=${PASSWORD:-147147}
ROOT_SIZE=${ROOT_SIZE:-12G}
ESP_SIZE=1G # the esp partition

PACKAGES=(fedora-release fedora-repos dnf5 rpm bash coreutils shadow-utils passwd
  sudo nano less which kbd util-linux iproute iputils procps-ng glibc-langpack-en
  systemd systemd-udev systemd-pam systemd-resolved systemd-boot-unsigned
  NetworkManager NetworkManager-wifi wpa_supplicant openssh-server openssh-clients
  dosfstools e2fsprogs
  # The phone, Denial, its services and apps
  linux-nx809j nx809j-device denial-nx809j phonewave-nx809j denial-apps-nx809j
  xdg-user-dirs kitty firefox mobile-config-firefox
  # Hardware
  mesa-dri-drivers mesa-vulkan-drivers pipewire pipewire-pulseaudio pipewire-alsa
  wireplumber alsa-utils bluez power-profiles-daemon)
SERVICES=(NetworkManager bluetooth nx809j-denial power-profiles-daemon
  systemd-resolved systemd-timesyncd)

[[ $(uname -m) == aarch64 && $(id -u) == 0 ]] || { echo "run as root on aarch64" >&2; exit 1; }
command -v dnf >/dev/null && command -v mkfs.fat >/dev/null ||
  { echo "needs dnf and dosfstools" >&2; exit 1; }

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

# Fedora's repositories (the host's configuration) plus ours. Scriptlets run
# chrooted in $M: they need /dev and /proc there
mkdir -p "$M/dev" "$M/proc"
mount --bind /dev "$M/dev"
mount -t proc proc "$M/proc"
dnf -y -q --installroot="$M" --releasever="$RELEASEVER" --use-host-config \
  --setopt=install_weak_deps=False \
  --repofrompath="nx809j,$REPO" --setopt=nx809j.gpgcheck=0 \
  install "${PACKAGES[@]}"
[[ -z ${FIRMWARE:-} ]] || tar -C "$M" --no-same-owner -xf "$FIRMWARE"

# The image's own dnf gets our repository from the release
cat > "$M/etc/yum.repos.d/nx809j.repo" <<EOF
[nx809j]
name=NX809J (RedMagic 11 Pro)
baseurl=${RELEASE_REPO//$(rpm -E %fedora)/\$releasever}
gpgcheck=0
# Our packages win over Fedora's, even newer ones: Fedora's next ffmpeg
# would drop the V4L2 fix until fedora/build-ffmpeg.sh rebuilds it
priority=10
EOF

cat > "$M/etc/fstab" <<'EOF'
# <file system>	<dir>	<type>	<options>	<dump>	<pass>
PARTLABEL=linux	/	ext4	rw,relatime,x-systemd.growfs	0 1
PARTLABEL=esp	/boot	vfat	rw,relatime,umask=0077,nofail	0 2
EOF
echo nx809j > "$M/etc/hostname"
echo LANG=en_US.UTF-8 > "$M/etc/locale.conf"
ln -sf ../usr/share/zoneinfo/UTC "$M/etc/localtime"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$M/etc/resolv.conf"
# The kernel has no SELinux
[[ ! -e $M/etc/selinux/config ]] || sed -i 's/^SELINUX=.*/SELINUX=disabled/' "$M/etc/selinux/config"

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

chroot "$M" /bin/bash -e <<EOF
systemd-sysusers
useradd -m -G wheel,audio,video,input,render,dmail "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
passwd -l root >/dev/null
systemctl enable ${SERVICES[*]}
# Fedora's presets turn these on. sshd stays off with a known password, as
# on the Arch image; dnf's metadata refresh would wake the phone hourly
systemctl disable sshd.service dnf-makecache.timer
EOF
umount "$M/proc" "$M/dev"
# The ESP is a loop device here, not a partition: relax bootctl's check
SYSTEMD_RELAX_ESP_CHECKS=1 bootctl install --root="$M" --esp-path=/boot --no-variables >/dev/null

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
rm -rf "$M"/var/cache/libdnf5/* "$M"/var/log/journal/* "$M/boot/loader/random-seed"
: > "$M/etc/machine-id"

# Give anything the chroot started a moment to let go of the mount
for i in 1 2 3 4 5; do umount -R "$M" 2>/dev/null && break; sleep 2; done
mountpoint -q "$M" && { echo "can't unmount $M" >&2; exit 1; }
e2fsck -fy "$OUT/linux.img" >/dev/null || true
resize2fs -M "$OUT/linux.img" >/dev/null 2>&1
blocks=$(dumpe2fs -h "$OUT/linux.img" 2>/dev/null | awk -F: '/^Block count/ { print $2 }')
truncate -s $((blocks * 4096)) "$OUT/linux.img"
ls -l "$OUT/linux.img" "$OUT/esp.img"
