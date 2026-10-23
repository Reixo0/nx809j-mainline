#!/usr/bin/env bash
# Serve a postmarketOS rootfs image to the phone over the USB network (NBD).
# Pair with a boot image built as: scripts/mkboot.sh nx809j.root=nbd
#
# Usage: scripts/nbd-root.sh [rootfs.img]
#   default: out/pmos/nubia-nx809j-root.img (scripts/pmos-prepare-root.sh)
#
# Needs no root. Only listens on the USB link address (172.16.42.2), so the
# image isn't exposed to the rest of the network. Keep it running while the
# phone uses the rootfs: stopping it hangs the phone's root filesystem.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG=${1:-$ROOT/out/pmos/nubia-nx809j-root.img}
ADDR=172.16.42.2
PORT=10809

[[ -f $IMG ]] || { echo "no rootfs image at $IMG" >&2; exit 1; }
echo "waiting for $ADDR (phone connected, nx809j-usb profile up)..."
until ip -4 addr | grep -q "inet $ADDR/"; do sleep 1; done
echo "serving $IMG on $ADDR:$PORT (Ctrl+C stops it; the phone's rootfs then hangs)"
# --shared=0 (no client limit): a phone that resets without disconnecting
# leaves a dead connection behind, and with the default single-client limit
# the next boot's nbd-client would wait on it forever. Only one phone ever
# uses the image; a dead connection can't write.
exec qemu-nbd --format=raw --bind="$ADDR" --port="$PORT" --persistent --shared=0 \
  --cache=writeback "$IMG"
