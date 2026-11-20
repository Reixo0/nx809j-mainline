# postmarketOS' Firefox configuration for phones. Without it the toolbar's
# minimum width overflows the 427 px wide (logical) screen. Fedora's Firefox
# lives in the libdir.
%global debug_package %{nil}

Name:           mobile-config-firefox
Version:        5.5.2
Release:        1%{?dist}
Summary:        Mobile and privacy friendly configuration for Firefox
License:        MPL-2.0
URL:            https://gitlab.postmarketos.org/postmarketOS/mobile-config-firefox
Source0:        %{url}/-/archive/%{version}/%{name}-%{version}.tar.gz
BuildRequires:  make
Requires:       firefox

%description
Firefox user interface and preferences adapted to phones, from postmarketOS.

%prep
%autosetup

%build

%install
%make_install FIREFOX_DIR=%{_libdir}/firefox

%files
%license LICENSE
%{_libdir}/firefox/*
/usr/lib/mobile-config-firefox
%{_datadir}/metainfo/eco.nura.mobile_config_firefox.metainfo.xml
