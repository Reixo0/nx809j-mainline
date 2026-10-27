#!/bin/sh
# Builds out/android-loader/nx809j-android.efi (clang + lld-link, no SDK).
set -eu
top=$(cd "$(dirname "$0")/../.." && pwd)
o=$top/out/android-loader
mkdir -p "$o"
clang -target aarch64-unknown-windows -ffreestanding -fno-stack-protector \
	-fshort-wchar -mgeneral-regs-only -fno-builtin -O2 -Wall -Werror \
	-c "$(dirname "$0")/loader.c" -o "$o/loader.o"
lld-link /subsystem:efi_application /entry:efi_main /nodefaultlib \
	/out:"$o/nx809j-android.efi" "$o/loader.o"
ls -l "$o/nx809j-android.efi"
