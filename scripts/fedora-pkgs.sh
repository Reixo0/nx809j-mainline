#!/usr/bin/env bash
# Prepare the Fedora RPMs of the NX809J: fills an rpmbuild tree with fedora/rpm/*.spec and
# their sources, our builds packed as tarballs.
#
#   linux-nx809j    <- out/kernel, out/modules (scripts/build.sh)
#   nx809j-device   <- device/rootfs + our audio topology
#   denial-nx809j, phonewave-nx809j, denial-apps-nx809j
#                   <- SYSROOT=<Fedora sysroot> STAGE=$STAGE scripts/build-denial.sh
#   qbootctl, tqftpserv, hexagonrpc, mobile-config-firefox, iris-vaapi
#                   <- built from source by fedora/build-rpms.sh
#
# Output: out/fedora/rpmbuild/{SPECS,SOURCES}. Building needs an aarch64
# Fedora host (the phone works): copy the tree there and run
# fedora/build-rpms.sh on it, which also makes the dnf repository.
# Usage: [STAGE=dir] scripts/fedora-pkgs.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
K=$ROOT/out/kernel
F=$ROOT/fedora
T=$ROOT/out/fedora/rpmbuild
DENIAL_BUILD=$(realpath "${DENIAL_BUILD:-$HOME/denial-build}")
STAGE=$(realpath -m "${STAGE:-$DENIAL_BUILD/stage-fedora}")
rm -rf "$T"
mkdir -p "$T/SPECS" "$T/SOURCES"
cp "$ROOT"/fedora/rpm/*.spec "$T/SPECS/"
cp "$ROOT/fedora/build-rpms.sh" "$T/"
pack() { tar -C "$1" --owner=0 --group=0 --sort=name --mtime=@0 \
  --exclude=__pycache__ -czf "$T/SOURCES/$2" .; }
# setspec SPEC VERSION [krel]
setspec() {
  sed -i "s/^Version:\( *\).*/Version:\1$2/" "$T/SPECS/$1.spec"
  [[ -z ${3:-} ]] || sed -i "s/^%global krel .*/%global krel $3/" "$T/SPECS/$1.spec"
}

# Kernel: Version from the release and the kernel tree's commit
rel=$(<"$K/include/config/kernel.release")
base=$(git -C "$ROOT/linux" describe --tags --abbrev=0 --match 'next-*')
n=$(git -C "$ROOT/linux" rev-list --count "$base..HEAD")
h=$(git -C "$ROOT/linux" rev-parse --short=9 HEAD)
mod=$ROOT/out/modules/lib/modules/$rel
[[ -d $mod ]] || { echo "no modules for $rel: run scripts/build.sh" >&2; exit 1; }
st=$ROOT/out/fedora/kernel; rm -rf "$st"; mkdir -p "$st/lib/modules"
cp "$K/arch/arm64/boot/Image" "$K/arch/arm64/boot/dts/qcom/kaanapali-nubia-nx809j.dtb" "$st/"
cp "$K/.config" "$st/config"
cp -a "$mod" "$st/lib/modules/"
pack "$st" kernel.tar.gz
cp "$ROOT/fedora/rpm/nx809j.conf" "$T/SOURCES/"
setspec linux-nx809j "${rel%%-*}.${base//-/}.r$n.g$h" "$rel"

# Device files: Version is the date and time of the last change to them
"$ROOT/scripts/build-topology.sh" >/dev/null
st=$ROOT/out/fedora/device; rm -rf "$st"; mkdir -p "$st"
cp -a "$ROOT/device/rootfs/usr" "$ROOT/device/rootfs/etc" "$st/"
install -Dm644 "$ROOT/out/audio/qcom/kaanapali/Nubia-NX809J-tplg.bin" \
  "$st/usr/lib/firmware/qcom/kaanapali/Nubia-NX809J-tplg.bin"
pack "$st" device-files.tar.gz
setspec nx809j-device "$(git -C "$ROOT" log -1 --format=%cd --date=format:%Y%m%d.%H%M -- device audio)"

# Denial, Phonewave's services and the apps. Version: the number of commits
# and the commit of each one's source
gitver() { echo "r$(git -C "$1" rev-list --count HEAD).g$(git -C "$1" rev-parse --short=9 HEAD)"; }
if [[ -d $STAGE/denial ]]; then
  pack "$STAGE/denial" denial.tar.gz
  cp "$F"/denial-nx809j/{nx809j-denial.service,nx809j-denial.tmpfiles,outputs.conf,denial-session.target,dev.denial.Settings.desktop} "$T/SOURCES/"
  setspec denial-nx809j "$(gitver "$DENIAL_BUILD/denial")"
  pack "$STAGE/phonewave" phonewave.tar.gz
  cp "$F/phonewave-nx809j/nx809j-sensors-hexagonrpcd.service" "$T/SOURCES/"
  setspec phonewave-nx809j "$(gitver "$DENIAL_BUILD/phonewave")"
  pack "$STAGE/apps" apps.tar.gz
  setspec denial-apps-nx809j "$(gitver "$DENIAL_BUILD/denial-apps")"
else
  echo "no $STAGE: leaving out Denial (scripts/build-denial.sh)" >&2
  rm "$T"/SPECS/{denial,phonewave,denial-apps}-nx809j.spec
fi

# Sources of the packages built from upstream
cp "$F/hexagonrpc/0001-hexagonrpcd-create-the-audio-PD.patch" "$T/SOURCES/"
cp "$ROOT"/fedora/iris-vaapi/*.patch "$T/SOURCES/"
ls -1 "$T/SPECS"
echo "now on an aarch64 Fedora host: fedora/build-rpms.sh <copy of $T>"
