# Fedora has no tqftpserv (only seen in review, bug 2221422). As
# archlinux/tqftpserv.
Name:           tqftpserv
Version:        1.3
Release:        1%{?dist}
Summary:        Trivial File Transfer Protocol server over QRTR
License:        BSD-3-Clause
URL:            https://github.com/linux-msm/tqftpserv
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz
BuildRequires:  gcc meson systemd-rpm-macros qrtr-devel libzstd-devel xz-devel
Requires:       qrtr

%description
Serves files to the modem and DSPs of Qualcomm SoCs over QRTR.

%prep
%autosetup

%build
%meson -Dsystemd-unit-prefix=%{_unitdir}
%meson_build

%install
%meson_install

%post
%systemd_post tqftpserv.service

%preun
%systemd_preun tqftpserv.service

%files
%license LICENSE
%{_bindir}/tqftpserv
%{_bindir}/populate-readwrite.sh
%{_unitdir}/tqftpserv.service
%{_unitdir}/tqftpserv-populate-readwrite.service
