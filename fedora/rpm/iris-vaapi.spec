# VA-API decode driver for the Iris video decoder (H.264, HEVC Main/Main10,
# VP9 profile 0/2). Upstream CFM880/iris-vaapi at a fixed commit, which
# targets the Xiaomi Pad 5; patches 0001-0002 come from the OnePlus Pad 4
# packaging (mzakamin-hub/iceland-mainline, packaging/iris-vaapi) for the
# HFI gen2 firmware this phone shares, 0003 lets it work inside Firefox's
# RDD sandbox. Needs the kernel's qcom_iris.decode_order_output (patch 0293);
# the option, the dma_heap rule and LIBVA_DRIVER_NAME=vpu for Denial's apps
# are in nx809j-device.
%global commit 9852479288b088699ae0c0b4c848dbda58bf7391
%global shortcommit 9852479
%global commitdate 20261023

Name:           iris-vaapi
Version:        0.2.0^%{commitdate}git%{shortcommit}
Release:        1.nx809j1%{?dist}
Summary:        VA-API decode driver for the Qualcomm Iris V4L2 video decoder
License:        GPL-2.0-or-later
URL:            https://github.com/CFM880/iris-vaapi
Source0:        %{url}/archive/%{commit}/%{name}-%{shortcommit}.tar.gz
Patch1:         0001-decode-skip-capture-pictures-without-a-client-timest.patch
Patch2:         0002-vaapi-report-YUV420-for-the-10-bit-profiles-too.patch
Patch3:         0003-Work-inside-Firefox-s-RDD-sandbox.patch

ExclusiveArch:  aarch64
BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  pkgconfig(libva)
BuildRequires:  pkgconfig(vulkan)
Requires:       libva
# Surfaces from the render node when a sandbox denies the DMA heap
Requires:       mesa-libgbm
Recommends:     libva-utils

%description
iris-vaapi (upstream name vpu-vaapi) passes the parameters and slices of
VA-API clients (Firefox, FFmpeg, mpv) as complete access units to the
stateful Qualcomm Iris V4L2 decoder (qcom_iris). Installed as
vpu_drv_video.so: select it with LIBVA_DRIVER_NAME=vpu.

%prep
%autosetup -p1 -n %{name}-%{commit}

%build
%make_build CC=gcc CFLAGS="%{optflags}" LDFLAGS="%{build_ldflags}" build/vpu_drv_video.so

%check
# upstream's hardware-independent unit tests
make CC=gcc CFLAGS="%{optflags}" LDFLAGS="%{build_ldflags}" check

%install
install -D -m 0755 build/vpu_drv_video.so %{buildroot}%{_libdir}/dri/vpu_drv_video.so

%files
%license COPYING
%doc README.md
%{_libdir}/dri/vpu_drv_video.so
