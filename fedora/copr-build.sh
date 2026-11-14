#!/usr/bin/env bash
# Build the NX809J's packages in COPR, Fedora's build service, which then
# hosts the dnf repository the images use. On a Fedora host (the phone works)
# with copr-cli set up: the owner's API token from
# https://copr.fedorainfracloud.org/api/ in ~/.config/copr.
#
# Makes source RPMs from the tree scripts/fedora-pkgs.sh prepares (our
# builds go in as tarballs, the rest is fetched from upstream) plus the
# patched FFmpeg (fedora/build-ffmpeg.sh), creates the project on first use
# and submits them all. COPR builds them for aarch64 on its own machines.
#
# Usage: fedora/copr-build.sh TOPDIR [PROJECT]   (PROJECT default: nx809j)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(realpath "${1:?usage: $0 TOPDIR [PROJECT]}")
PROJECT=${2:-nx809j}
CHROOT=fedora-$(rpm -E %fedora)-aarch64
need=()
command -v rpmbuild >/dev/null || need+=(rpm-build)
command -v spectool >/dev/null || need+=(rpmdevtools)
command -v copr-cli >/dev/null || need+=(copr-cli)
[[ ${#need[@]} == 0 ]] || sudo dnf -y install "${need[@]}"
copr-cli whoami >/dev/null || { echo "copr-cli has no token: ~/.config/copr" >&2; exit 1; }

if ! copr-cli get "$PROJECT" >/dev/null 2>&1; then
  copr-cli create "$PROJECT" --chroot "$CHROOT" \
    --description "Mainline Linux for the Nubia RedMagic 11 Pro (NX809J): kernel, device files, Denial and the phone services" \
    --instructions "Images from https://github.com/Reixo0/nx809j-mainline come with this repository set up."
fi

cd "$T"
rm -rf SRPMS
for s in SPECS/*.spec; do
  spectool -g -C SOURCES "$s" >/dev/null
  rpmbuild --define "_topdir $T" -bs "$s" >/dev/null
done
SRPM_ONLY=1 "$ROOT/fedora/build-ffmpeg.sh" "$T/SRPMS" >/dev/null
ls -1 SRPMS
for f in SRPMS/*.src.rpm; do
  copr-cli build --nowait --chroot "$CHROOT" "$PROJECT" "$f"
done
echo "builds submitted: https://copr.fedorainfracloud.org/coprs/$(copr-cli whoami)/$PROJECT/builds/"
