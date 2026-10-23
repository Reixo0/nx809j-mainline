#!/usr/bin/env bash
# Build a probe (probe/<name>.S) into a flashable/bootable image:
#   out/probe-<variant>.img  (same format ABL accepts: v4, Image.gz+DTB, AVB footer)
# Usage: probe/build.sh <name> [variant] [assembler flags...]
#   e.g. probe/build.sh dtbcheck canoe -DNEEDLE='"qcom,canoe"' 
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
name=${1:?usage: probe/build.sh <name> [variant] [asflags...]}
variant=${2:-$name}; shift $(( $# < 2 ? $# : 2 ))
O=$ROOT/out/probe/$variant; mkdir -p "$O"
clang --target=aarch64-none-elf "$@" -c "$ROOT/probe/$name.S" -o "$O/$name.o"
ld.lld --image-base=0 -Ttext=0 --entry=_start "$O/$name.o" -o "$O/$name.elf"
llvm-objcopy -O binary "$O/$name.elf" "$O/Image"
gzip -9 -n -f -k "$O/Image"
KERNEL=gz KERNEL_IMAGE="$O/Image.gz" OUT="$ROOT/out/probe-$variant.img" "$ROOT/scripts/mkboot.sh"
