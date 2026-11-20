# Phonewave's device services the NX809J uses: hapticd (vibration), steinerd
# (sensors), braun (cameras), dmail (modem) and callaudio (call audio),
# cross-built by scripts/build-denial.sh from
# https://github.com/denialwm/phonewave and packed into phonewave.tar.gz by
# scripts/fedora-pkgs.sh, which also sets Version. Its fingerprint stack is left out: that writes
# to persist and RPMB.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           phonewave-nx809j
Version:        0
Release:        1%{?dist}
Summary:        Vibration, sensor, camera, modem and call audio services for the NX809J
License:        MIT
URL:            https://github.com/denialwm/phonewave
ExclusiveArch:  aarch64
AutoReqProv:    no
Source0:        phonewave.tar.gz
Source1:        nx809j-sensors-hexagonrpcd.service
Requires:       hexagonrpc alsa-lib alsa-utils alsa-ucm-utils pipewire-libs
Requires:       pulseaudio-utils dbus
Requires(post): systemd

%description
Phonewave's vibration, sensor, camera, modem and call audio services, built
for the Nubia RedMagic 11 Pro.

%prep
%setup -q -c

%build

%install
cp -dR --preserve=mode,timestamps usr etc %{buildroot}/
install -Dm644 %{SOURCE1} %{buildroot}/usr/lib/systemd/system/nx809j-sensors-hexagonrpcd.service
# Its services start at boot (the sensor registry has to be up before the
# ADSP starts, or the sensors stay missing until it restarts)
w=%{buildroot}/usr/lib/systemd/system/multi-user.target.wants
install -d $w
for u in hapticd steinerd braun dmail nx809j-sensors-hexagonrpcd; do
  ln -s ../$u.service $w/$u.service
done
w=%{buildroot}/usr/lib/systemd/user/default.target.wants
install -d $w
for u in callaudio braun-loopback; do ln -s ../$u.service $w/$u.service; done
cd %{buildroot}
find . -mindepth 1 \( -type f -o -type l \) -printf '/%%P\n' |
  sed 's|^/etc/.*|%%config(noreplace) "&"|; t; s|.*|"&"|' > %{_builddir}/files.list
find . -mindepth 1 -type d -printf '/%%P\n' | while read -r d; do
  rpm -qf --quiet "$d" 2>/dev/null || echo "%%dir \"$d\""
done >> %{_builddir}/files.list

%post
# New users (dmail, braun) and the D-Bus policies for their names
systemd-sysusers >/dev/null 2>&1 || :
systemd-tmpfiles --create >/dev/null 2>&1 || :
busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || :

%files -f %{_builddir}/files.list
