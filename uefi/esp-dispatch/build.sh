#!/bin/sh
# Builds out/esp-dispatch/BOOTAA64.EFI (clang + lld-link, no SDK).
set -eu
top=$(cd "$(dirname "$0")/../.." && pwd)
o=$top/out/esp-dispatch
mkdir -p "$o"
clang -target aarch64-unknown-windows -ffreestanding -fno-stack-protector \
	-fshort-wchar -mgeneral-regs-only -fno-builtin -O2 -Wall -Werror \
	-c "$(dirname "$0")/dispatch.c" -o "$o/dispatch.o"
lld-link /subsystem:efi_application /entry:efi_main /nodefaultlib \
	/out:"$o/BOOTAA64.EFI" "$o/dispatch.o"
ls -l "$o/BOOTAA64.EFI"
