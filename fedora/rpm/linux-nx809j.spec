# NX809J: mainline kernel for the Nubia RedMagic 11 Pro, built by
# scripts/build.sh from https://github.com/Reixo0/linux (branch nx809j) and
# packed into kernel.tar.gz by scripts/fedora-pkgs.sh, which also sets Version
# and krel.
#
# Image and DTB stay in /usr/lib/modules/<krel> (RPM has no business on the
# FAT ESP); %%posttrans copies them to /boot/nx809j, where systemd-boot loads
# them, and adds the loader entry on first install.
%global krel 0
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           linux-nx809j
Version:        0
Release:        1%{?dist}
Summary:        Mainline Linux for the Nubia RedMagic 11 Pro (NX809J)
License:        GPL-2.0-only
URL:            https://github.com/Reixo0/linux
ExclusiveArch:  aarch64
AutoReqProv:    no
Source0:        kernel.tar.gz
Source1:        nx809j.conf
Requires:       kmod
Requires(posttrans): coreutils kmod
# The Adreno 840 microcode (xz-compressed: the kernel reads it so)
Recommends:     qcom-firmware

%description
Kernel image, device tree and modules for the Nubia RedMagic 11 Pro. The
phone's own firmware is not here: firmware/nx809j-firmware.sh copies it from
Android.

%prep
%setup -q -c

%build

%install
m=%{buildroot}/usr/lib/modules/%{krel}
install -d %{buildroot}/usr/lib/modules
cp -dR --preserve=mode,timestamps lib/modules/%{krel} %{buildroot}/usr/lib/modules/
rm -f $m/build $m/source
install -m644 Image kaanapali-nubia-nx809j.dtb $m/
install -m644 config $m/config
echo %{name} > $m/pkgbase
install -Dm644 %{SOURCE1} %{buildroot}/usr/share/%{name}/nx809j.conf

%posttrans
depmod -a %{krel}
if [ -d /boot ]; then
  m=/usr/lib/modules/%{krel}
  mkdir -p /boot/nx809j
  for f in Image kaanapali-nubia-nx809j.dtb; do
    cp $m/$f /boot/nx809j/.$f.new && mv -f /boot/nx809j/.$f.new /boot/nx809j/$f
  done
  # The entry is the user's once there: kernel options get edited
  if [ ! -e /boot/loader/entries/nx809j.conf ]; then
    mkdir -p /boot/loader/entries
    cp /usr/share/%{name}/nx809j.conf /boot/loader/entries/nx809j.conf
  fi
  sync -f /boot/nx809j/Image
fi

%files
/usr/lib/modules/%{krel}
/usr/share/%{name}
