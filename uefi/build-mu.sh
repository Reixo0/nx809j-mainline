#!/bin/sh
# Builds Mu-Silicium for the NX809J from the mu-silicium-nx809j submodule
# with this repository's inputs: the phone's uefi_a dump, our kernel's DTB,
# avbtool and the Mu-Silicium checkout in tools/dl. Arguments and FB_MARKER,
# ABL_PROBE, SKIP_DXE as for that repository's build.sh; the image lands in
# uefi/mu-silicium-nx809j/out/.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
UEFI_IMG=${UEFI_IMG:-$top/dump/partitions/uefi_a.img} \
DTB=${DTB:-$top/out/kernel/arch/arm64/boot/dts/qcom/kaanapali-nubia-nx809j.dtb} \
AVBTOOL=${AVBTOOL:-$top/tools/avb/avbtool.py} \
MU=${MU:-$top/tools/dl/Mu-Silicium} \
PY=${PY:-$top/tools/dl/mu-venv/bin/python3} \
	exec "$top/uefi/mu-silicium-nx809j/build.sh" "$@"
