#!/usr/bin/env bash
# Rebuild Fedora's FFmpeg (the ffmpeg-free packages: libavcodec-free and the
# rest) with archlinux/ffmpeg-nx809j's patch, which makes seeking work with
# V4L2 hardware decoding. On an aarch64 Fedora host (the phone works).
#
# The release gets a .nx809j1 suffix so the packages win over Fedora's same
# build; a newer Fedora ffmpeg wins over them again (and drops the patch)
# until this is run on it.
#
# Output: the binary RPMs (no debuginfo, no devel) in OUTDIR, for
# fedora/build-rpms.sh's repo (EXTRA_RPMS=OUTDIR).
# Usage: fedora/build-ffmpeg.sh OUTDIR
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH=$ROOT/archlinux/ffmpeg-nx809j/0001-avcodec-v4l2_m2m_dec-flush-on-seek-resume-after-LAST.patch
OUT=$(realpath -m "${1:?usage: $0 OUTDIR}")
[[ $(uname -m) == aarch64 ]] || { echo "run on aarch64" >&2; exit 1; }
command -v rpmbuild >/dev/null || sudo dnf -y install rpm-build
T=$(mktemp -d /var/tmp/ffmpeg-nx809j.XXXXXX)
trap 'rm -rf "$T"' EXIT
cd "$T"
dnf -q download --source ffmpeg-free
rpm --define "_topdir $T" -i ffmpeg-*.src.rpm
cp "$PATCH" SOURCES/
s=SPECS/ffmpeg.spec
# %autosetup -S git_am applies every PatchN in order
sed -i "/^Patch1002:/a Patch2001:      $(basename "$PATCH")" "$s"
sed -i 's/^\(Release:\s*\S*\)%{?dist}$/\1%{?dist}.nx809j1/' "$s"
grep -q '^Patch2001:' "$s" && grep -q '^Release:.*nx809j1' "$s" ||
  { echo "the spec changed: Patch/Release lines not found" >&2; exit 1; }
sudo dnf -y builddep "$s"
rpmbuild --define "_topdir $T" --nocheck -bb "$s" >build.log 2>&1 ||
  { tail -n 40 build.log >&2; exit 1; }
mkdir -p "$OUT"
find RPMS -name '*.rpm' ! -name '*-debuginfo-*' ! -name '*-debugsource-*' \
  ! -name '*-devel-*' -exec cp {} "$OUT/" \;
ls -1 "$OUT"
