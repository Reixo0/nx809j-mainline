#!/usr/bin/env bash
# Build the mainline kernel + NX809J DTB with clang/LLVM (no cross gcc needed).
# Usage: scripts/build.sh [config|kernel|dtbs|modules|all]   (default: all)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KSRC=$ROOT/linux
OUT=$ROOT/out/kernel
DTB=qcom/kaanapali-nubia-nx809j.dtb
MAKE=(make -C "$KSRC" O="$OUT" ARCH=arm64 LLVM=1 -j"$(nproc)")

config() {
  mkdir -p "$OUT"
  "${MAKE[@]}" defconfig
  "$KSRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$ROOT/configs/nx809j.config"
  # Bring-up initramfs is built into the kernel (see scripts/mkinitramfs.sh)
  "$KSRC/scripts/config" --file "$OUT/.config" \
    --set-str INITRAMFS_SOURCE "$ROOT/out/initramfs.cpio" \
    --enable INITRAMFS_COMPRESSION_GZIP
  "${MAKE[@]}" olddefconfig
  # Report fragment options that didn't stick (missing deps or typos)
  while IFS='=' read -r k v; do
    [[ $k =~ ^CONFIG_ ]] || continue
    got=$(grep -E "^$k=|^# $k is not set" "$OUT/.config" || echo "$k (absent)")
    [[ $got == "$k=$v" || ( $v == n && $got == "# $k is not set" ) ]] || echo "warn: wanted $k=$v, got: $got"
  done < "$ROOT/configs/nx809j.config"
}

kernel()  { "$ROOT/scripts/mkinitramfs.sh"; "${MAKE[@]}" Image.gz; }
dtbs()    { "${MAKE[@]}" "$DTB"; }
modules() {
  "${MAKE[@]}" modules
  rm -rf "$ROOT/out/modules"
  "${MAKE[@]}" INSTALL_MOD_PATH="$ROOT/out/modules" INSTALL_MOD_STRIP=1 modules_install
}

case ${1:-all} in
  config)  "$ROOT/scripts/mkinitramfs.sh"; config ;;
  kernel)  kernel ;;
  dtbs)    dtbs ;;
  modules) modules ;;
  all)     [[ -f $OUT/.config ]] || { "$ROOT/scripts/mkinitramfs.sh"; config; }; kernel; dtbs; modules ;;
  *) echo "usage: $0 [config|kernel|dtbs|modules|all]" >&2; exit 1 ;;
esac
