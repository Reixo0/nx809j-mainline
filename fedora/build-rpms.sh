#!/usr/bin/env bash
# Build the NX809J's RPMs and their dnf repository on an aarch64 Fedora host
# (the phone works), from the tree scripts/fedora-pkgs.sh prepares (this
# script is copied into it). Downloads the upstream sources the specs name
# and installs their build dependencies (sudo dnf builddep).
#
# Output: TOPDIR/repo, with repodata/ for dnf.
# Usage: [EXTRA_RPMS=dir] fedora/build-rpms.sh TOPDIR
#   EXTRA_RPMS  more RPMs for the repository (fedora/build-ffmpeg.sh's output)
set -euo pipefail
T=$(realpath "${1:?usage: $0 TOPDIR}")
[[ $(uname -m) == aarch64 ]] || { echo "run on aarch64" >&2; exit 1; }
need=()
command -v rpmbuild >/dev/null || need+=(rpm-build)
command -v spectool >/dev/null || need+=(rpmdevtools)
command -v createrepo_c >/dev/null || need+=(createrepo_c)
[[ ${#need[@]} == 0 ]] || sudo dnf -y install "${need[@]}"

cd "$T"
specs=(SPECS/*.spec)
for s in "${specs[@]}"; do
  spectool -g -C SOURCES "$s" >/dev/null
done
sudo dnf -y builddep "${specs[@]}"
rm -rf RPMS repo
for s in "${specs[@]}"; do
  echo "== $s"
  rpmbuild --define "_topdir $T" -bb "$s" >"$T/$(basename "$s" .spec).log" 2>&1 ||
    { tail -n 30 "$T/$(basename "$s" .spec).log" >&2; exit 1; }
done
mkdir -p repo
find RPMS -name '*.rpm' ! -name '*-debuginfo-*' ! -name '*-debugsource-*' -exec cp {} repo/ \;
# Packages built elsewhere (fedora/build-ffmpeg.sh)
[[ -z ${EXTRA_RPMS:-} ]] || cp "$EXTRA_RPMS"/*.rpm repo/
createrepo_c -q repo
ls -1 repo
