#!/usr/bin/env bash
# Build the boot shim: out/shim/shim.bin (+ shim-off.bin debug variant that
# powers off after a successful merge instead of entering Linux).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/shim
FDT=$ROOT/linux/scripts/dtc/libfdt
O=$ROOT/out/shim; mkdir -p "$O"
CFLAGS=(--target=aarch64-none-elf -O2 -ffreestanding -fno-builtin -nostdlib
  -mgeneral-regs-only -mstrict-align -fPIE -fno-stack-protector
  -fno-asynchronous-unwind-tables -Wall -I"$SRC/include" -I"$SRC" -I"$FDT")

objs=()
for f in "$SRC/shim.c" "$FDT"/fdt.c "$FDT"/fdt_ro.c "$FDT"/fdt_rw.c "$FDT"/fdt_wip.c "$FDT"/fdt_addresses.c; do
  o=$O/$(basename "${f%.c}").o
  clang "${CFLAGS[@]}" -c "$f" -o "$o"; objs+=("$o")
done

for variant in shim shim-off; do
  extra=(); [[ $variant == shim-off ]] && extra=(-DSHIM_DEBUG_OFF)
  clang "${CFLAGS[@]}" "${extra[@]}" -c "$SRC/head.S" -o "$O/head-$variant.o"
  ld.lld -T "$SRC/shim.ld" --emit-relocs -o "$O/$variant.elf" "$O/head-$variant.o" "${objs[@]}"
  # The shim isn't relocated: refuse anything that stores an absolute address
  if llvm-readelf -r "$O/$variant.elf" | grep -qE 'R_AARCH64_(ABS|PREL64|GLOB_DAT|RELATIVE)'; then
    llvm-readelf -r "$O/$variant.elf" | grep -E 'R_AARCH64_(ABS|PREL64|GLOB_DAT|RELATIVE)' >&2
    echo "error: absolute relocations in $variant" >&2; exit 1
  fi
  llvm-objcopy -O binary "$O/$variant.elf" "$O/$variant.bin"
  size=$(stat -c %s "$O/$variant.bin")
  (( size <= 0x10000 )) || { echo "error: $variant is $size bytes, max 64 KiB" >&2; exit 1; }
  echo "$variant.bin: $size bytes"
done
