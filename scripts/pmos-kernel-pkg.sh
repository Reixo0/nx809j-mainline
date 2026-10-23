#!/usr/bin/env bash
# Package our kernel build for postmarketOS and install the NX809J port into
# the pmaports checkout pmbootstrap uses (tools/pmaports).
#
#   pmos/linux-nubia-nx809j/kernel.tar.gz   <- out/kernel (Image, dtb, config)
#   tools/pmaports/device/testing/{device,linux}-nubia-nx809j  <- pmos/*
#
# Run after scripts/build.sh, then: pmbootstrap build --force linux-nubia-nx809j
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
K=$ROOT/out/kernel
PKG=$ROOT/pmos/linux-nubia-nx809j
APORTS=${APORTS:-$ROOT/tools/pmaports}
STAGE=$ROOT/out/pmos-kernel

rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$K/arch/arm64/boot/Image" "$STAGE/Image"
cp "$K/arch/arm64/boot/dts/qcom/kaanapali-nubia-nx809j.dtb" "$STAGE/"
cp "$K/.config" "$STAGE/config"
# postmarketOS finds the kernel release via /usr/lib/modules/<release>; ship
# the built-in module lists even when no modules are packaged
cp "$K/include/config/kernel.release" "$K/modules.builtin" "$K/modules.builtin.modinfo" "$STAGE/"
if [[ ${INCLUDE_MODULES:-0} == 1 && -d $ROOT/out/modules/lib/modules ]]; then
  cp -a "$ROOT/out/modules/lib" "$STAGE/"
fi
tar -C "$STAGE" --owner=0 --group=0 --sort=name --mtime=@0 -czf "$PKG/kernel.tar.gz" .

# Refresh checksums the way `pmbootstrap checksum` would
python3 -I - "$ROOT/pmos" <<'PY'
import hashlib, pathlib, re, sys
for apkbuild in sorted(pathlib.Path(sys.argv[1]).glob("*/APKBUILD")):
    # sha512sums is always last: drop it (and anything a bad run left) and redo it
    text = apkbuild.read_text().split('\nsha512sums="')[0].rstrip("\n") + "\n"
    srcs = re.search(r'^source="([^"]*)"', text, re.M).group(1).split()
    sums = "".join(
        f"{hashlib.sha512((apkbuild.parent / s).read_bytes()).hexdigest()}  {s}\n" for s in srcs)
    apkbuild.write_text(text + f'\nsha512sums="\n{sums}"\n')
PY

mkdir -p "$APORTS/device/testing"
for pkg in "$ROOT/pmos"/*/; do
  name=$(basename "$pkg")
  rm -rf "$APORTS/device/testing/$name"
  cp -a "$pkg" "$APORTS/device/testing/$name"
done
echo "kernel.tar.gz: $(du -h "$PKG/kernel.tar.gz" | cut -f1); port installed in $APORTS/device/testing"
