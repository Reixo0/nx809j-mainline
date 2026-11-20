# Fedora has no qbootctl. It must be on the phone
# before the first boot: nx809j-mark-boot-successful.service uses it, or ABL
# counts slot a down.
Name:           qbootctl
Version:        0.2.2
Release:        1%{?dist}
Summary:        Qualcomm bootloader A/B slot control
License:        GPL-3.0-only
URL:            https://github.com/linux-msm/qbootctl
Source0:        %{url}/archive/refs/tags/%{version}/%{name}-%{version}.tar.gz
BuildRequires:  gcc meson

%description
Reads and sets the A/B slot state that Qualcomm's bootloader keeps in the GPT.

%prep
%autosetup

%build
%meson
%meson_build

%install
%meson_install

%files
%license LICENSE
%{_bindir}/qbootctl
