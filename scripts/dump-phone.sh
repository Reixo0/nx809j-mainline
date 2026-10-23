#!/usr/bin/env bash
# Dump everything useful for mainline bring-up from a rooted NX809J over adb.
# Usage: scripts/dump-phone.sh [outdir]   (default: dump/)
set -euo pipefail
OUT=${1:-"$(dirname "$0")/../dump"}
SLOT=$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')
mkdir -p "$OUT"/{partitions,runtime,firmware}
su() { adb exec-out su -c "$*"; }

# Partitions too big or useless to dump (user data, whole disks, crash logs).
SKIP='^(super|userdata|sd[a-z]|logdump|rawdump|vm-bootsys_.|vm-persist|ALIGN_.*)$'

echo "== partitions (active slot $SLOT + unslotted)"
for p in $(su 'ls -1 /dev/block/by-name' | tr -d '\r'); do
  [[ $p =~ $SKIP ]] && continue
  [[ $p == *_a || $p == *_b ]] && [[ $p != *"$SLOT" ]] && continue
  f="$OUT/partitions/$p.img"
  [[ -s $f ]] && continue
  printf '%s ' "$p"
  su "cat /dev/block/by-name/$p" > "$f"
done
echo
(cd "$OUT/partitions" && sha256sum ./*.img > SHA256SUMS)

echo "== runtime state"
R="$OUT/runtime"
su 'cat /sys/firmware/fdt'          > "$R/live.dtb"
su 'dmesg'                          > "$R/dmesg.txt"
su 'cat /proc/iomem'                > "$R/iomem.txt"
su 'cat /proc/interrupts'           > "$R/interrupts.txt"
su 'cat /proc/cmdline'              > "$R/cmdline.txt"
su 'cat /proc/cpuinfo'              > "$R/cpuinfo.txt"
su 'lsmod'                          > "$R/lsmod.txt"
su 'getprop'                        > "$R/getprop.txt"
su 'ls -lR /sys/bus/i2c/devices/ /sys/bus/spi/devices/ /sys/bus/platform/devices/' > "$R/buses.txt"
# debugfs is usually not mounted on user builds; mount it temporarily.
su 'mount -t debugfs none /sys/kernel/debug 2>/dev/null'; true
su 'cat /sys/kernel/debug/gpio'                     > "$R/gpio.txt" || true
su 'cat /sys/kernel/debug/pinctrl/*/pinmux-pins'    > "$R/pinmux.txt" || true
su 'cat /sys/kernel/debug/regulator/regulator_summary' > "$R/regulators.txt" || true
su 'cat /sys/kernel/debug/clk/clk_summary'          > "$R/clk_summary.txt" || true
dtc -q -I dtb -O dts "$R/live.dtb" -o "$R/live.dts"

echo "== firmware"
for d in /vendor/firmware_mnt /vendor/firmware /vendor/dsp /vendor/bt_firmware /odm/firmware /vendor/etc/acdbdata; do
  if ! su "test -d $d"; then echo "skip $d"; continue; fi
  dest="$OUT/firmware/$(echo "${d#/}" | tr / _)"
  mkdir -p "$dest"
  su "tar -C $d -cf - ." | tar -C "$dest" -xf - || echo "warn: tar of $d failed"
  chmod -R u+w "$dest"
done
echo "done -> $OUT"
