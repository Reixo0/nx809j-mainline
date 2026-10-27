#!/bin/sh
# Capture the display pipeline's state on the phone, to compare a boot with
# the speckled screen against a clean one. Run as root with the screen on:
#   sudo display-state.sh [outdir]   (default: /var/tmp/display-state-<time>)
# Saves the DRM/msm debugfs files, the framebuffers' formats and modifiers,
# and the MDSS UBWC registers read through /dev/mem.
set -eu
OUT=${1:-/var/tmp/display-state-$(date +%Y%m%d-%H%M%S)}
D=/sys/kernel/debug/dri/1
mkdir -p "$OUT"
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug

for f in state framebuffer gem clients kms name debug/sspp debug/vbif debug/core_perf debug/danger debug/core_irq; do
  cat "$D/$f" > "$OUT/$(echo "$f" | tr / _).txt" 2>&1 || true
done
dmesg > "$OUT/dmesg.txt"
uname -a > "$OUT/uname.txt"
cat /proc/cmdline >> "$OUT/uname.txt"

# MDSS top-level UBWC registers (msm_mdss.c: UBWC_DEC_HW_VERSION 0x58,
# UBWC_STATIC 0x144, UBWC_CTRL_2 0x150, UBWC_PREDICTION_MODE 0x154).
# Only while MDSS is powered: reading it suspended hangs the bus and resets
# the SoC.
if [ "$(cat /sys/bus/platform/devices/9800000.display-subsystem/power/runtime_status)" != active ]; then
  echo "MDSS is suspended (screen off?): registers not read" | tee "$OUT/mdss-ubwc.txt"
else
python3 -I - "$OUT/mdss-ubwc.txt" <<'EOF'
import mmap, os, struct, sys
base, regs = 0x9800000, {"UBWC_DEC_HW_VERSION": 0x58, "UBWC_STATIC": 0x144,
                         "UBWC_CTRL_2": 0x150, "UBWC_PREDICTION_MODE": 0x154}
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=base)
with open(sys.argv[1], "w") as f:
    for name, off in regs.items():
        f.write("%-22s 0x%08x\n" % (name, struct.unpack_from("<I", m, off)[0]))
EOF
fi
echo "saved to $OUT"
grep -E "format=|modifier=" "$OUT/framebuffer.txt" | sort | uniq -c
cat "$OUT/mdss-ubwc.txt"
