# Serves the ADSP's sensor and audio configuration. Fedora has no hexagonrpc.
# With fedora/hexagonrpc's audio PD patch (Source1, copied from there by
# scripts/fedora-pkgs.sh).
%global commit da7a3742ab8d5273a281b70ee11f16fb2cb6a690
%global shortcommit %(c=%{commit}; echo ${c:0:7})

Name:           hexagonrpc
Version:        0.5^%{shortcommit}
Release:        1%{?dist}
Summary:        FastRPC client libraries and reverse tunnel daemon for Hexagon DSPs
License:        GPL-3.0-or-later
URL:            https://github.com/linux-msm/hexagonrpc
Source0:        %{url}/archive/%{commit}/%{name}-%{shortcommit}.tar.gz
Patch0:         0001-hexagonrpcd-create-the-audio-PD.patch
BuildRequires:  gcc meson systemd-rpm-macros

%description
hexagonrpcd answers the file requests of Qualcomm Hexagon DSPs (their sensor
and audio configuration) over FastRPC.

%prep
%autosetup -n %{name}-%{commit} -p1

%build
%meson
%meson_build

%install
%meson_install
# Its units land under the libdir; systemd reads /usr/lib
install -d %{buildroot}%{_unitdir}
mv %{buildroot}%{_libdir}/systemd/system/hexagonrpcd-*.service %{buildroot}%{_unitdir}/
rm -rf %{buildroot}%{_libdir}/systemd

%files
%license COPYING
%{_bindir}/hexagonrpcd
%{_libexecdir}/hexagonrpc
%{_libdir}/libhexagonrpc.so*
%{_unitdir}/hexagonrpcd-*.service
%{_mandir}/man1/hexagonrpcd.1*
