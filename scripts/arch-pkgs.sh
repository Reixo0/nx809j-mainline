#!/usr/bin/env bash
# Build the Arch Linux ARM packages and the [nx809j] pacman repository:
#
#   linux-nx809j    <- out/kernel, out/modules (scripts/build.sh)
#   nx809j-device   <- device/rootfs + our audio topology
#   + every *.pkg.tar.* in PKGS_FROM (qrtr, rmtfs, tqftpserv, qbootctl,
#     mobile-config-firefox: built natively with makepkg on an aarch64 host)
#
# Output: out/arch/repo/ with nx809j.db, uploaded as a GitHub release.
# Usage: PKGS_FROM=dir scripts/arch-pkgs.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
K=$ROOT/out/kernel
A=$ROOT/archlinux
REPO=$ROOT/out/arch/repo
mkdir -p "$REPO"

# Packages hold no compiled code of their own, so the host's makepkg can
# build them for aarch64
conf=$ROOT/out/arch/makepkg.conf
cat > "$conf" <<'EOF'
source /etc/makepkg.conf
CARCH=aarch64
CHOST=aarch64-unknown-linux-gnu
PKGEXT=.pkg.tar.zst
PACKAGER='Reixo <125610085+Reixo0@users.noreply.github.com>'
EOF
build() {
  (cd "$1" && makepkg --config "$conf" -f --nodeps --noconfirm --cleanbuild PKGDEST="$REPO" >/dev/null)
  rm -rf "$1/src" "$1/pkg"
}
setver() { sed -i "s/^pkgver=.*/pkgver=$2/" "$1/PKGBUILD"; }

# Kernel: pkgver from the release and the kernel tree's commit
rel=$(<"$K/include/config/kernel.release")
base=$(git -C "$ROOT/linux" describe --tags --abbrev=0 --match 'next-*')
n=$(git -C "$ROOT/linux" rev-list --count "$base..HEAD")
h=$(git -C "$ROOT/linux" rev-parse --short=9 HEAD)
mod=$ROOT/out/modules/lib/modules/$rel
[[ -d $mod ]] || { echo "no modules for $rel: run scripts/build.sh" >&2; exit 1; }
st=$ROOT/out/arch/kernel; rm -rf "$st"; mkdir -p "$st/lib/modules"
cp "$K/arch/arm64/boot/Image" "$K/arch/arm64/boot/dts/qcom/kaanapali-nubia-nx809j.dtb" "$st/"
cp "$K/.config" "$st/config"
cp "$K/include/config/kernel.release" "$st/"
cp -a "$mod" "$st/lib/modules/"
tar -C "$st" --owner=0 --group=0 --sort=name --mtime=@0 -czf "$A/linux-nx809j/kernel.tar.gz" .
setver "$A/linux-nx809j" "${rel%%-*}.${base//-/}.r$n.g$h"
build "$A/linux-nx809j"

# Device files: pkgver is the date of the last change to them
"$ROOT/scripts/build-topology.sh" >/dev/null
st=$ROOT/out/arch/device; rm -rf "$st"; mkdir -p "$st"
cp -a "$ROOT/device/rootfs/usr" "$st/"
install -Dm644 "$ROOT/out/audio/qcom/kaanapali/Nubia-NX809J-tplg.bin" \
  "$st/usr/lib/firmware/qcom/kaanapali/Nubia-NX809J-tplg.bin"
tar -C "$st" --owner=0 --group=0 --sort=name --mtime=@0 -czf "$A/nx809j-device/device-files.tar.gz" .
setver "$A/nx809j-device" "$(git -C "$ROOT" log -1 --format=%cd --date=format:%Y%m%d -- device audio)"
build "$A/nx809j-device"

if [[ -n ${PKGS_FROM:-} ]]; then
  cp "$PKGS_FROM"/*.pkg.tar.* "$REPO/"
fi

# Only the newest of each package goes into the database
rm -f "$REPO"/nx809j.{db,files}*
shopt -s nullglob
(cd "$REPO" && repo-add -q -n -R nx809j.db.tar.gz ./*.pkg.tar.{zst,xz} 2>/dev/null)
ls -1 "$REPO"
