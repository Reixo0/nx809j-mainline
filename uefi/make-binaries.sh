#!/bin/sh
# Builds the NX809J vendor binaries for Mu-Silicium (Binaries/nx809j) from
# the phone's own uefi partition: extracts the drivers, applies
# uefi/patch-dxe.py and puts each driver next to its .inf (matched by GUID).
#
# Usage: uefi/make-binaries.sh [uefi.img] [Mu-Silicium dir]
# The drivers are Qualcomm/Nubia binaries from the phone: they stay out of
# git, only the .inf files are in uefi/Binaries/nx809j.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
img=${1:-$top/dump/partitions/uefi_a.img}
mu=${2:-$top/tools/dl/Mu-Silicium}
out=$mu/Binaries/nx809j
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 -I "$top/uefi/fv-extract.py" "$img" "$work/fv" > "$work/list.txt"
python3 -I "$top/uefi/patch-dxe.py" "$work/fv"

rm -rf "$out"
mkdir -p "$out"
cp -r "$top/uefi/Binaries/nx809j/." "$out/"

# GUID -> extracted directory
find "$work/fv" -name '*.guid' | while read -r g; do
	echo "$(cut -d' ' -f1 "$g") $(dirname "$g")"
done > "$work/guids"

find "$out" -name '*.inf' | while read -r inf; do
	guid=$(sed -n 's/^ *FILE_GUID *= *\([^ ]*\).*/\1/p' "$inf" | tr a-f A-F)
	src=$(awk -v g="$guid" '$1 == g { print $2 }' "$work/guids")
	if [ -z "$src" ]; then
		echo "no driver for $inf ($guid)" >&2
		exit 1
	fi
	for f in $(sed -n 's/^ *[A-Z0-9_]*|\([^|]*\)|.*/\1/p' "$inf"); do
		cp "$src/$f" "$(dirname "$inf")/"
	done
done

mkdir -p "$out/RawFiles"
for f in SecParti.cfg BDS_Menu.cfg; do
	cp "$work/fv/$f/$f" "$out/RawFiles/"
done
echo "$(find "$out" -name '*.efi' | wc -l) drivers in $out"
