# Denial, cross-built by scripts/build-denial.sh (SYSROOT= a Fedora sysroot)
# from https://github.com/denialwm/denial and packed into denial.tar.gz by
# scripts/fedora-pkgs.sh, which also sets Version. The session runs on tty1 from nx809j-denial.service, adapted from Phonewave
# (devices/nx809j, MIT).
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           denial-nx809j
Version:        0
Release:        1%{?dist}
Summary:        Denial, a Wayland compositor and mobile shell, for the NX809J
License:        GPL-3.0-or-later
URL:            https://github.com/denialwm/denial
ExclusiveArch:  aarch64
# Flutter's bundled libraries would turn into provides
AutoReqProv:    no
Source0:        denial.tar.gz
Source1:        nx809j-denial.service
Source2:        nx809j-denial.tmpfiles
Source3:        outputs.conf
Source4:        denial-session.target
Source5:        dev.denial.Settings.desktop
Provides:       denial
Requires:       nx809j-device systemd-pam libinput libseat wayland-utils
Requires:       xorg-x11-server-Xwayland polkit mesa-dri-drivers mesa-libEGL mesa-libgbm
Requires:       libdrm libxkbcommon xkeyboard-config gtk3 zenity rtkit ddcutil
Requires:       xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
Requires:       google-noto-sans-fonts google-noto-color-emoji-fonts
Requires:       google-noto-sans-cjk-fonts dejavu-sans-fonts liberation-fonts
Requires(post): systemd

%description
Denial, a Wayland compositor and mobile shell, set up for the Nubia RedMagic
11 Pro.

%prep
%setup -q -c

%build

%install
d=%{buildroot}
install -d $d/usr/lib/denial $d/usr/bin
cp -dR --preserve=mode,timestamps native shell settings polkit source-commit $d/usr/lib/denial/
ln -s ../lib/denial/settings/denial-settings $d/usr/bin/denial-settings
for b in denialctl denial-portal denial-polkit-agent; do
  ln -s ../lib/denial/native/$b $d/usr/bin/$b
done
install -Dm644 portal/denial-polkit-agent.service $d/usr/lib/systemd/user/denial-polkit-agent.service
install -Dm644 portal/denial-portal.service $d/usr/lib/systemd/user/denial-portal.service
install -Dm644 portal/denial-portals.conf $d/usr/share/xdg-desktop-portal/denial-portals.conf
install -Dm644 portal/denial.portal $d/usr/share/xdg-desktop-portal/portals/denial.portal
install -Dm644 portal/org.freedesktop.impl.portal.desktop.denial.service \
  $d/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service
install -Dm644 portal/xdg-desktop-portal-wlr-Denial $d/etc/xdg/xdg-desktop-portal-wlr/Denial
install -Dm644 %{SOURCE1} $d/usr/lib/systemd/system/nx809j-denial.service
install -Dm644 %{SOURCE2} $d/usr/lib/tmpfiles.d/nx809j-denial.conf
install -Dm644 %{SOURCE3} $d/usr/share/nx809j/outputs.conf
install -Dm644 %{SOURCE4} $d/usr/lib/systemd/user/denial-session.target
install -Dm644 %{SOURCE5} $d/usr/share/applications/dev.denial.Settings.desktop

%post
systemd-tmpfiles --create nx809j-denial.conf >/dev/null 2>&1 || :

%files
/usr/lib/denial
/usr/bin/denial-settings
/usr/bin/denialctl
/usr/bin/denial-portal
/usr/bin/denial-polkit-agent
/usr/lib/systemd/user/denial-polkit-agent.service
/usr/lib/systemd/user/denial-portal.service
/usr/lib/systemd/user/denial-session.target
/usr/share/xdg-desktop-portal/denial-portals.conf
/usr/share/xdg-desktop-portal/portals/denial.portal
/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service
%config(noreplace) /etc/xdg/xdg-desktop-portal-wlr/Denial
/usr/lib/systemd/system/nx809j-denial.service
/usr/lib/tmpfiles.d/nx809j-denial.conf
%dir /usr/share/nx809j
/usr/share/nx809j/outputs.conf
/usr/share/applications/dev.denial.Settings.desktop
