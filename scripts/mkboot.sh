#!/usr/bin/env bash
# Package out/kernel Image.gz + NX809J DTB + initramfs into a boot image
# for `fastboot boot` (RAM only, nothing is flashed).
#
# Usage: [FORMAT=v4|v2] [KERNEL=shim|gz|raw] [SHIM=shim|shim-off] [KERNEL_IMAGE=path]
#        [OUT=path] scripts/mkboot.sh [extra cmdline...]
#   KERNEL=shim (default): shim/ in front of the kernel. ABL passes the
#     downstream DTB from vendor_boot, never ours; the shim merges what ABL
#     filled in into our DTB (which carries the cmdline in /chosen/bootargs).
#   SHIM=shim-off: debug shim that powers off after a successful merge.
#   KERNEL_IMAGE: use this kernel file instead of out/kernel (e.g. a probe)
# Output: out/boot.img (or $OUT)
#
# v4 (default): what this ABL accepts. Same layout Mu-Silicium uses for the
#   OnePlus 15 (same SoC/board-id): kernel = Image.gz with the DTB appended,
#   no dtb section. ABL still takes vendor_boot from the partition, so its
#   ramdisk and cmdline get merged with ours; our files use unique paths.
# v2: kernel + ramdisk + dtb section. Rejected by the NX809J ABL with
#   "Invalid Parameter"; kept for comparison.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
K=$ROOT/out/kernel/arch/arm64/boot
DTB=$K/dts/qcom/kaanapali-nubia-nx809j.dtb
FORMAT=${FORMAT:-v4}
KERNEL=${KERNEL:-shim}    # gz/raw = plain kernel, gets the downstream DTB
SHIM=${SHIM:-shim}
OUT=${OUT:-$ROOT/out/boot.img}
# ABL rejects images whose header os_version/patch level are unset
# ("Invalid Parameter"); mirror the stock boot_a header.
OS_VERSION=${OS_VERSION:-16.0.0}
OS_PATCH_LEVEL=${OS_PATCH_LEVEL:-2026-08}
BOOT_PART_SIZE=100663296   # boot_a, 96 MiB

# Keep the bootloader-initialized display/clocks alive for simplefb.
# mem_sleep_default=s2idle: suspend as Android does (CPUs in their deepest
# idle states). PSCI SYSTEM_SUSPEND ("deep") returns from the firmware within
# ~10 ms, so the phone would wake right away.
# panic=10: warm-reboot 10 s after a panic (time for a photo). A warm reset
# keeps RAM, so the log survives in pstore; a long power-button press often
# doesn't. ABL counts these as failed boots and drops to fastboot after a few.
CMDLINE="console=tty0 loglevel=7 ignore_loglevel clk_ignore_unused pd_ignore_unused \
fbcon=font:TER16x32 rdinit=/nx809j-init mem_sleep_default=s2idle panic=10 $*"

# Our init is built into the kernel (scripts/mkinitramfs.sh). Still pass a
# copy as the boot.img ramdisk (lz4 legacy, like the stock vendor ramdisk it
# gets appended to) so the image keeps the layout ABL accepted.
"$ROOT/scripts/mkinitramfs.sh"
lz4 -l -9 -q -f "$ROOT/out/initramfs.cpio" "$ROOT/out/initramfs.cpio.lz4"

MKBOOTIMG=(python3 "$ROOT/tools/mkbootimg/mkbootimg.py"
  --os_version "$OS_VERSION" --os_patch_level "$OS_PATCH_LEVEL")
case $FORMAT in
  v4)
    case $KERNEL in
      gz) KIMG=$K/Image.gz ;;
      raw) KIMG=$K/Image ;;
      shim)
        "$ROOT/shim/build.sh" >/dev/null
        cp "$DTB" "$ROOT/out/shim/nx809j.dtb"
        fdtput -t s "$ROOT/out/shim/nx809j.dtb" /chosen bootargs "$CMDLINE"
        python3 -I "$ROOT/shim/mkshim.py" "$ROOT/out/shim/$SHIM.bin" \
          "$ROOT/out/shim/nx809j.dtb" "${KERNEL_IMAGE:-$K/Image}" "$ROOT/out/shim/Image"
        gzip -9 -n -f -k "$ROOT/out/shim/Image"
        KIMG=$ROOT/out/shim/Image.gz ;;
      *) echo "KERNEL must be shim, gz or raw" >&2; exit 1 ;;
    esac
    [[ $KERNEL == shim ]] || KIMG=${KERNEL_IMAGE:-$KIMG}
    cat "$KIMG" "$DTB" > "$ROOT/out/kernel-dtb.$KERNEL"
    "${MKBOOTIMG[@]}" --header_version 4 \
      --kernel "$ROOT/out/kernel-dtb.$KERNEL" \
      --ramdisk "$ROOT/out/initramfs.cpio.lz4" \
      --cmdline "$CMDLINE" \
      -o "$OUT"
    ;;
  v2)
    "${MKBOOTIMG[@]}" --header_version 2 \
      --kernel "$K/Image.gz" \
      --ramdisk "$ROOT/out/initramfs.cpio.lz4" \
      --dtb "$DTB" \
      --base 0x0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 \
      --tags_offset 0x100 --dtb_offset 0x1f00000 --pagesize 4096 \
      --cmdline "$CMDLINE" \
      -o "$OUT"
    ;;
  *) echo "FORMAT must be v4 or v2" >&2; exit 1 ;;
esac
# Stock boot_a carries an unsigned AVB hash footer at the end of the 96 MiB
# partition; ABL's load/auth path reads it, so add the same.
python3 "$ROOT/tools/avb/avbtool.py" add_hash_footer \
  --image "$OUT" --partition_name boot \
  --partition_size "$BOOT_PART_SIZE" --algorithm NONE \
  --prop "com.android.build.boot.os_version:${OS_VERSION%%.*}" \
  --prop "com.android.build.boot.security_patch:${OS_PATCH_LEVEL}-01"
echo "$FORMAT/$KERNEL: $(ls -lh "$OUT" | awk '{print $5, $9}')"
