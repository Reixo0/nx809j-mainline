#!/usr/bin/env bash
# Install the phone's own "peach" Wi-Fi firmware (copied from Android into
# dump/firmware/wifi-bt, not redistributable) into the running rootfs over
# SSH, under the names ath12k looks for in ath12k/PEACH/hw2.0:
#
#   amss.bin       <- peach/amss20.bin       (loaded over MHI)
#   m3.bin         <- peach/phy_ucode20.elf  (cnss2 sends it as the M3 file)
#   aux_ucode.bin  <- peach/aux_ucode20.elf
#   board.bin      <- peach/bdwlan.elf       (the board file Android loads)
#   regdb.bin      <- peach/regdb.bin
#   qdss_trace_config.cfg <- peach/qdss_trace_config_v2.cfg (fw waits for it)
#
# and the Bluetooth (Brahma, WCN7860-style) rampatch and NVM files into qca/:
#   brhbtfw20.mbn, brhbtnv20.*   (from Android's /vendor/bt_firmware)
#
# scripts/pmos-add-firmware.sh puts the same files into a rootfs image offline.
#
# Usage: scripts/install-wifi-firmware.sh [user@host]   (default reixo@172.16.42.1)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOST=${1:-reixo@172.16.42.1}
SRC=$ROOT/dump/firmware/wifi-bt/peach
DIR=/usr/lib/firmware/ath12k/PEACH/hw2.0

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$SRC/amss20.bin" "$STAGE/amss.bin"
cp "$SRC/phy_ucode20.elf" "$STAGE/m3.bin"
cp "$SRC/aux_ucode20.elf" "$STAGE/aux_ucode.bin"
cp "$SRC/bdwlan.elf" "$STAGE/board.bin"
cp "$SRC/regdb.bin" "$STAGE/regdb.bin"
cp "$SRC/qdss_trace_config_v2.cfg" "$STAGE/qdss_trace_config.cfg"

tar -C "$STAGE" --owner=0 --group=0 -czf - . | ssh "$HOST" "
  set -e
  sudo mkdir -p $DIR
  sudo tar -xzf - -C $DIR --no-same-permissions
  # the staging dir is mode 700 (mktemp) and tar applies that to $DIR
  sudo chmod 755 $DIR
  sudo sh -c 'chmod 644 $DIR/*'
  ls -l $DIR"

BT=$ROOT/dump/firmware/wifi-bt/bt
tar -C "$BT" --owner=0 --group=0 -czf - brhbtfw20.mbn $(cd "$BT" && ls brhbtnv20.*) | ssh "$HOST" "
  set -e
  sudo mkdir -p /usr/lib/firmware/qca
  sudo rm -f /usr/lib/firmware/qca/gngbt*
  sudo tar -xzf - -C /usr/lib/firmware/qca --no-same-permissions
  sudo sh -c 'chmod 644 /usr/lib/firmware/qca/brhbt*'
  ls /usr/lib/firmware/qca | grep brhbt | tr '\\n' ' '; echo"
