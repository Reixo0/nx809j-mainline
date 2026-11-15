# NX809J: the device files (device/rootfs: services, rmtfs drop-in, udev
# rules, UCM, ...) and our AudioReach topology, packed into
# device-files.tar.gz by scripts/fedora-pkgs.sh, which also sets Version.
# As archlinux/nx809j-device. The phone's own firmware is not here:
# firmware/nx809j-firmware.sh copies it from Android.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global __brp_mangle_shebangs %{nil}

Name:           nx809j-device
Version:        0
Release:        1%{?dist}
Summary:        Device support files for the Nubia RedMagic 11 Pro (NX809J)
License:        GPL-2.0-only
URL:            https://github.com/Reixo0/nx809j-mainline
BuildArch:      noarch
AutoReqProv:    no
Source0:        device-files.tar.gz
Requires:       linux-nx809j qcom-firmware qrtr rmtfs tqftpserv qbootctl
Requires:       NetworkManager NetworkManager-wifi e2fsprogs bluez alsa-ucm
Requires:       python3 python3-evdev python3-xlib geoclue2 libgpiod-utils
Requires:       iio-sensor-proxy zram-generator pipewire-utils
Requires(posttrans): systemd

%description
Services, udev rules, ALSA UCM, the AudioReach topology and the rest of what
the NX809J needs on top of Fedora.

%prep
%setup -q -c

%build

%install
cp -dR --preserve=mode,timestamps usr etc %{buildroot}/
cd %{buildroot}
# Files in /etc are the user's to edit: an update leaves an edited one be
find . -mindepth 1 \( -type f -o -type l \) -printf '"/%%P"\n' |
  sed 's|^"/etc/|%%config(noreplace) "/etc/|' > %{_builddir}/files.list
# Our own directories (those no other package owns)
find . -mindepth 1 -type d -printf '/%%P\n' | while read -r d; do
  rpm -qf --quiet "$d" 2>/dev/null || echo "%%dir \"$d\""
done >> %{_builddir}/files.list

%posttrans
# Enable what 80-nx809j.preset names on first install; later changes are
# the user's
# (shell only: a fresh image has no awk)
if [ ! -e /var/lib/nx809j-device/preset-done ]; then
  units=
  while read -r action unit; do
    [ "$action" = enable ] && units="$units $unit"
  done < /usr/lib/systemd/system-preset/80-nx809j.preset
  if systemctl preset $units; then
    mkdir -p /var/lib/nx809j-device && touch /var/lib/nx809j-device/preset-done
  fi
fi

%files -f %{_builddir}/files.list
