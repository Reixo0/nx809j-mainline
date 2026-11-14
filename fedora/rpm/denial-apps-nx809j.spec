# Denial's phone apps, cross-built by scripts/build-denial.sh from
# https://github.com/denialwm/denial-apps and packed into apps.tar.gz by
# scripts/fedora-pkgs.sh, which also sets Version. As
# archlinux/denial-apps-nx809j: named denial-* in /usr/bin ("settings" and
# "camera" are too generic for a system path); Messages stays "messages".
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           denial-apps-nx809j
Version:        0
Release:        1%{?dist}
Summary:        Denial's Camera, Sensors, Phone Settings, Calls and Messages apps
License:        LicenseRef-Sustainable-Use-1.0 AND CC-BY-SA-4.0
URL:            https://github.com/denialwm/denial-apps
ExclusiveArch:  aarch64
AutoReqProv:    no
Source0:        apps.tar.gz
Requires:       phonewave-nx809j denial-nx809j mesa-vulkan-drivers vulkan-loader
Requires:       pipewire pipewire-utils sound-theme-freedesktop

%description
Denial's Camera, Sensors, Phone Settings, Calls and Messages apps for the
Nubia RedMagic 11 Pro.

%prep
%setup -q -c

%build

%install
cp -dR --preserve=mode,timestamps usr %{buildroot}/
w=%{buildroot}/usr/lib/systemd/user/graphical-session.target.wants
install -d $w
for u in calls-ringer messages-notifier; do ln -s ../$u.service $w/$u.service; done
cd %{buildroot}
find . -mindepth 1 \( -type f -o -type l \) -printf '"/%%P"\n' > %{_builddir}/files.list
find . -mindepth 1 -type d -printf '/%%P\n' | while read -r d; do
  rpm -qf --quiet "$d" 2>/dev/null || echo "%%dir \"$d\""
done >> %{_builddir}/files.list

%files -f %{_builddir}/files.list
