#!/usr/bin/env bash
# Print the phone's firmware files for the rootfs, one per line, as
# "<path under /usr/lib/firmware>:<source file>". Used by
# scripts/pmos-add-firmware.sh (offline image) and
# scripts/install-device-files.sh (any rootfs directory).
#
# Sources: out/firmware (scripts/pack-firmware.py, from the phone's firmware
# partitions), the private dump/ (Wi-Fi/BT, modem extras, speaker tuning) and
# our audio topology. The Adreno 840 microcode (qcom/gen80200_*) comes from
# the distribution's linux-firmware-qcom package. On the phone itself,
# firmware/nx809j-firmware.sh does the same from Android.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FW=$ROOT/out/firmware/lib/firmware
DEV=qcom/kaanapali/nubia/nx809j

files="$DEV/gen80200_zap.mbn
  $DEV/adsp.mbn $DEV/adsp_dtb.mbn $DEV/cdsp.mbn $DEV/cdsp_dtb.mbn
  $DEV/soccp.mbn $DEV/soccp_dtb.mbn
  $DEV/modem.mbn $DEV/modem_dtb.mbn $DEV/ipa_fws.mbn"
for f in $files; do
  echo "$f:$FW/$f"
done

# The modem loads these over tqftpserv from next to modem.mbn: its MBN
# configuration (modem_pr), OEM software (modem_oem) and their manifest
IMAGE=$ROOT/dump/firmware/vendor_firmware_mnt/image
echo "$DEV/modemr.jsn:$IMAGE/modemr.jsn"
(cd "$IMAGE" && find modem_pr modem_oem -type f | sort) | while read -r f; do
  echo "$DEV/$f:$IMAGE/$f"
done

# Wi-Fi (peach) from the phone's own vendor files, under ath12k's names, as
# scripts/install-wifi-firmware.sh does: "<name in ath12k/PEACH/hw2.0>:<source>"
WIFI=$ROOT/dump/firmware/wifi-bt/peach
for p in amss.bin:amss20.bin m3.bin:phy_ucode20.elf aux_ucode.bin:aux_ucode20.elf \
    board.bin:bdwlan.elf regdb.bin:regdb.bin qdss_trace_config.cfg:qdss_trace_config_v2.cfg; do
  echo "ath12k/PEACH/hw2.0/${p%%:*}:$WIFI/${p#*:}"
done
# Bluetooth (Brahma) rampatch and board NVM files, same names in qca/
for f in "$ROOT"/dump/firmware/wifi-bt/bt/brhbtfw20.mbn "$ROOT"/dump/firmware/wifi-bt/bt/brhbtnv20.*; do
  echo "qca/${f##*/}:$f"
done

# Audio: our AudioReach topology (scripts/build-topology.sh) and the speaker
# amplifiers' tuning file from the phone's vendor firmware
"$ROOT"/scripts/build-topology.sh >/dev/null 2>&1
echo "qcom/kaanapali/Nubia-NX809J-tplg.bin:$ROOT/out/audio/qcom/kaanapali/Nubia-NX809J-tplg.bin"
echo "$DEV/aw88461_acf.bin:$ROOT/dump/firmware/vendor_firmware/aw882xx_acf.bin"
