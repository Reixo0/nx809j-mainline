#!/usr/bin/env bash
# RAM-boot out/boot.img on the phone. Nothing is flashed: a hard reboot
# (hold power ~15s) returns to Android.
#
# The stock fastboot refuses `boot`; this needs the efisp/gbl-chainload
# "superfastboot" (hold vol-up while the phone boots). Enter it by hand.
#
# A rejected image doesn't change anything right away: ABL marks slot a
# unbootable on the *next* reboot, which lands in the stock fastboot. Fix it by
# hand from superfastboot: fastboot set_active a && fastboot reboot
# (only ever slot a: slot b has never booted and runs its own abl_b).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG=${1:-$ROOT/out/boot.img}   # usage: scripts/boot.sh [image]

fastboot devices | grep -q . || echo "Put the phone in superfastboot (vol-up during boot), waiting..."
until fastboot devices | grep -q .; do sleep 1; done
echo "sending $IMG"
fastboot getvar unlocked 2>&1 | grep -q 'unlocked: *yes' || {
  echo "fastboot reports locked: this isn't superfastboot, 'boot' will be refused" >&2; exit 1; }
fastboot getvar current-slot 2>&1 | grep -q 'current-slot: *a' || {
  echo "current slot isn't a; not touching anything" >&2; exit 1; }

if ! fastboot boot "$IMG"; then
  echo "== rejected. Still in superfastboot: you can retry other images now."
  echo "   After the next reboot slot a will be unbootable (see header)."
  exit 1
fi
cat <<EOF
Sent. If USB comes up: telnet 172.16.42.1 (host gets 172.16.42.2 via DHCP).
If it hangs: hold power ~15s, re-enable slot a from superfastboot if needed,
then, in Android: scripts/get-pstore.sh
EOF
