#!/bin/bash
# Build and install the Qualcomm tools Fedora does not ship, natively on the
# phone (aarch64), from the same sources as fedora/rpm/{qbootctl,tqftpserv,
# hexagonrpc}.spec. qbootctl must be there before Fedora's first boot:
# nx809j-mark-boot-successful.service uses it, or ABL counts slot a down.
# Usage: sudo fedora/build-qcom-tools.sh [DESTDIR]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-}
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT
cd "$B"
curl -sfL https://github.com/linux-msm/qbootctl/archive/refs/tags/0.2.2.tar.gz | tar xz
curl -sfL https://github.com/linux-msm/tqftpserv/archive/refs/tags/v1.3.tar.gz | tar xz
git clone -q https://github.com/linux-msm/hexagonrpc.git
git -C hexagonrpc checkout -q da7a374
git -C hexagonrpc apply "$ROOT/fedora/hexagonrpc/0001-hexagonrpcd-create-the-audio-PD.patch"
M=(meson setup --prefix=/usr --libdir=lib64 --buildtype=plain)
"${M[@]}" qbootctl-0.2.2 b-qbootctl
"${M[@]}" tqftpserv-1.3 b-tqftpserv -Dsystemd-unit-prefix=/usr/lib/systemd/system
"${M[@]}" hexagonrpc b-hexagonrpc
for d in b-qbootctl b-tqftpserv b-hexagonrpc; do
  meson compile -C "$d"
  DESTDIR=$DEST meson install -C "$d" --no-rebuild
done
# hexagonrpc puts its units under the libdir; systemd reads /usr/lib
mkdir -p "$DEST/usr/lib/systemd/system"
mv "$DEST"/usr/lib64/systemd/system/hexagonrpcd-*.service "$DEST/usr/lib/systemd/system/"
rmdir "$DEST/usr/lib64/systemd/system" "$DEST/usr/lib64/systemd" 2>/dev/null || true
[[ -n $DEST ]] || ldconfig
