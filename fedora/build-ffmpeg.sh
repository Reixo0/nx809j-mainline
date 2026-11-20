#!/usr/bin/env bash
# Rebuild Fedora's FFmpeg (the ffmpeg-free packages: libavcodec-free and the
# rest) with fedora/ffmpeg-nx809j's patch, which makes seeking work with
# V4L2 hardware decoding. On an aarch64 Fedora host (the phone works).
#
# The release gets a .nx809j1 suffix so the packages win over Fedora's same
# build; a newer Fedora ffmpeg wins over them again (and drops the patch)
# until this is run on it.
#
# Output: the binary RPMs (no debuginfo, no devel) in OUTDIR, for
# fedora/build-rpms.sh's repo (EXTRA_RPMS=OUTDIR).
# SRPM_ONLY=1 makes only the patched source RPM instead, for COPR
# (fedora/copr-build.sh).
# DECODERS="name ..." enables more decoders than Fedora's list (e.g. the
# hardware ones Fedora leaves out), RELEASE_TAG changes the suffix.
# Usage: [SRPM_ONLY=1] [DECODERS=...] [RELEASE_TAG=nx809j1] fedora/build-ffmpeg.sh OUTDIR
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=${RELEASE_TAG:-nx809j1}
PATCH=$ROOT/fedora/ffmpeg-nx809j/0001-avcodec-v4l2_m2m_dec-flush-on-seek-resume-after-LAST.patch
OUT=$(realpath -m "${1:?usage: $0 OUTDIR}")
[[ $(uname -m) == aarch64 ]] || { echo "run on aarch64" >&2; exit 1; }
command -v rpmbuild >/dev/null || sudo dnf -y install rpm-build
T=$(mktemp -d /var/tmp/ffmpeg-nx809j.XXXXXX)
trap 'rm -rf "$T"' EXIT
cd "$T"
# Fedora's own source of its newest build: asked by name, as our repository
# wins for ffmpeg-free (and has no sources)
v=$(dnf -q repoquery --repo=fedora --repo=updates --latest-limit=1 --arch="$(uname -m)" \
  --qf '%{version}-%{release}\n' ffmpeg-free | tail -n 1)
dnf -q download --repo=fedora-source --repo=updates-source "ffmpeg-$v.src"
rpm --define "_topdir $T" -i ffmpeg-*.src.rpm
cp "$PATCH" SOURCES/
s=SPECS/ffmpeg.spec
# %autosetup -S git_am applies every PatchN in order
sed -i "/^Patch1002:/a Patch2001:      $(basename "$PATCH")" "$s"
sed -i "s/^\(Release:\s*\S*\)%{?dist}$/\1%{?dist}.$TAG/" "$s"
grep -q '^Patch2001:' "$s" && grep -q "^Release:.*$TAG" "$s" ||
  { echo "the spec changed: Patch/Release lines not found" >&2; exit 1; }
for d in ${DECODERS:-}; do echo "$d" >> SOURCES/enable_decoders; done
mkdir -p "$OUT"
if [[ -n ${SRPM_ONLY:-} ]]; then
  rpmbuild --define "_topdir $T" -bs "$s" >/dev/null
  cp SRPMS/*.src.rpm "$OUT/"
  ls -1 "$OUT"
  exit 0
fi
sudo dnf -y builddep "$s"
rpmbuild --define "_topdir $T" --nocheck -bb "$s" >build.log 2>&1 ||
  { tail -n 40 build.log >&2; exit 1; }
mkdir -p "$OUT"
find RPMS -name '*.rpm' ! -name '*-debuginfo-*' ! -name '*-debugsource-*' \
  ! -name '*-devel-*' -exec cp {} "$OUT/" \;
ls -1 "$OUT"
