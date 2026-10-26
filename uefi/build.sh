#!/bin/sh
# Builds Mu-Silicium (UEFI) for the NX809J into out/Mu-nx809j.img, a boot
# image for boot_a.
#
# Usage: uefi/build.sh [RELEASE|DEBUG]
#
# Needs: tools/dl/Mu-Silicium with its submodules (except Binaries),
# tools/dl/mu-venv (pip install -r Mu-Silicium/pip-requirements.txt),
# nasm and mono on the host, dump/partitions/uefi_a.img, and a kernel build
# in out/kernel for the DTB that UEFI hands to Linux.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
mu=$top/tools/dl/Mu-Silicium
py=$top/tools/dl/mu-venv/bin/python3
target=${1:-RELEASE}
dtb=$top/out/kernel/arch/arm64/boot/dts/qcom/kaanapali-nubia-nx809j.dtb

# Our package, config and DTB inside the Mu tree
mkdir -p "$mu/Platforms/ZTE"
ln -sfn "$top/uefi/nx809jPkg" "$mu/Platforms/ZTE/nx809jPkg"
ln -sf "$top/uefi/nx809j.toml" "$mu/Resources/Configs/nx809j.toml"
cp "$dtb" "$top/uefi/nx809jPkg/FdtBlob/kaanapali-nubia-nx809j.dtb"
# Appended to the kernel for ABL's board matching (ABL on this phone passes
# its own downstream DTB anyway).
cp "$dtb" "$mu/Resources/DTBs/nx809j.dtb"

"$top/uefi/make-binaries.sh" "$top/dump/partitions/uefi_a.img" "$mu"

cd "$mu"
"$py" build_uefi.py -d nx809j -r "$target"

# The NX809J ABL wants the unsigned AVB hash footer that stock boot_a has
# (see scripts/mkboot.sh).
mkdir -p "$top/out"
cp Mu-nx809j.img "$top/out/Mu-nx809j.img"
python3 "$top/tools/avb/avbtool.py" add_hash_footer \
	--image "$top/out/Mu-nx809j.img" --partition_name boot \
	--partition_size 100663296 --algorithm NONE \
	--prop com.android.build.boot.os_version:16 \
	--prop com.android.build.boot.security_patch:2026-08-01
ls -l "$top/out/Mu-nx809j.img"
