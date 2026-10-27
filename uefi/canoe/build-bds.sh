#!/usr/bin/env bash
# Build Canoe's BDS.efi with the nx809j big-font console patch.
#
# Usage: uefi/canoe/build-bds.sh [canoe checkout]
#   default checkout: tools/dl/gbl_root_canoe (clone of
#   github.com/1vivy/gbl_root_canoe at ae950bb, release 7.0.11)
# Output: out/canoe/BDS.efi
#
# Runs on the host instead of the project's Docker image: same make
# invocation as submodules/uefi/Makefile `build`, with host fixes:
#   EXTRA_OPTFLAGS=-Wno-error  newer clang warns in BaseTools (Elf64Convert.c)
#   HOST_WARNINGS              same for the firmware code (clang 23 vs the
#                              image's clang 20), added to tools_def.txt
#   PYTHON_COMMAND=mu-venv     BaseTools' tests need distutils (Python >= 3.12
#                              only has it through setuptools)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CANOE=${1:-$ROOT/tools/dl/gbl_root_canoe}
PATCH=$ROOT/uefi/canoe/canoe-big-console.patch
OUT=$ROOT/out/canoe

[ "$(git -C "$CANOE" rev-parse --short=7 HEAD)" = ae950bb ] ||
	echo "warning: $CANOE is not at ae950bb (7.0.11)" >&2

if git -C "$CANOE" apply --check "$PATCH" 2>/dev/null; then
	git -C "$CANOE" apply "$PATCH"
elif ! git -C "$CANOE" apply --check -R "$PATCH" 2>/dev/null; then
	echo "$PATCH neither applies nor is applied" >&2
	exit 1
fi

VERSION=$(sed -n 's/^CANOE_VERSION *:\?= *//p' "$CANOE/version.mk")
export PYTHON_COMMAND=$ROOT/tools/dl/mu-venv/bin/python3
export EXTRA_OPTFLAGS=-Wno-error
HOST_WARNINGS="-Wno-unknown-warning-option -Wno-unused-but-set-global"

cd "$CANOE/submodules/uefi"
cp -r Conf edk2/
sed -i "s/^\(DEFINE CLANG35_WARNING_OVERRIDES *=.*\)/\1 $HOST_WARNINGS/" edk2/Conf/tools_def.txt
"$PYTHON_COMMAND" embed_variant.py blobs/canoe-usbmsd.efi \
	edk2/QcomModulePkg/Application/LinuxLoader/Generated/CanoeMsdVariantData.c
"$PYTHON_COMMAND" embed_variant.py blobs/canoe-managed-msd.efi \
	edk2/QcomModulePkg/Application/LinuxLoader/Generated/CanoeManagedMsdVariantData.c CanoeManagedMsd
# Canoe's Makefile notes that EDK2 reuses stale objects; always rebuild BDS.
rm -rf edk2/Build/RELEASE_CLANG35
(
	cd edk2
	set +u  # edksetup.sh reads unset variables
	. ./edksetup.sh
	make BOARD_BOOTLOADER_PRODUCT_NAME=canoe CANOE_VERSION="$VERSION" \
		TARGET_ARCHITECTURE=AARCH64 TARGET=RELEASE \
		CLANG_BIN=/usr/bin/ CLANG_PREFIX=aarch64-linux-gnu- VERIFIED_BOOT_ENABLED=1 \
		VERIFIED_BOOT_LE=0 AB_RETRYCOUNT_DISABLE=0 TARGET_BOARD_TYPE_AUTO=0 \
		BUILD_USES_RECOVERY_AS_BOOT=0 DISABLE_PARALLEL_DOWNLOAD_FLASH=0 PVMFW_BCC_ENABLED=-DPVMFW_BCC \
		REMOVE_CARVEOUT_REGION=1 QSPA_BOOTCONFIG_ENABLE=1 USER_BUILD_VARIANT=0 TEST_ADAPTER=1 \
		PREBUILT_HOST_TOOLS="BUILD_CC=clang BUILD_CXX=clang++ LDPATH=-fuse-ld=lld BUILD_AR=llvm-ar"
)
mkdir -p "$OUT"
cp edk2/Build/RELEASE_CLANG35/AARCH64/LinuxLoader.efi "$OUT/BDS.efi"
sha256sum "$OUT/BDS.efi"
