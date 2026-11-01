#!/bin/sh
# Save the phone's cell connection to dump/cell/, for the 5G work. Works with
# whichever system is up: Android over adb, Linux over ssh. Stays private: the
# output has cell IDs, which give the phone's location.
#   scripts/cell-log.sh            one snapshot
#   scripts/cell-log.sh 60         one every 60 seconds, until Ctrl-C
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/dump/cell
SSH="ssh -o ConnectTimeout=3 -o BatchMode=yes -o UserKnownHostsFile=$HOME/.ssh/known_hosts.nx809j-arch alarm@172.16.42.1"
mkdir -p "$OUT"

android() {
  adb shell dumpsys telephony.registry | sed -n '/^last known state/,/^local logs/p' |
    grep -E 'Phone Id=|mServiceState=|mSignalStrength=|mTelephonyDisplayInfo=|mPhysicalChannelConfigs=|mDataConnectionNetworkType=|mCellIdentity=|mBarringInfo='
  adb shell dumpsys phone | grep -E 'isImsRegistered|mPreferredNetworkType|mAllowedNetworkTypes' | head -5
  adb logcat -d -b radio -t 2000 | grep -E 'isImsRegistered|getImsRegistrationTechnology|PHYSICAL_CHANNEL|nrState|rejectCause' | tail -20
}
linux() {
  $SSH 'date -u +%FT%TZ; dmailctl status; ip -o route show default; \
    journalctl -b -u dmail --no-pager -n 30 2>/dev/null'
}
snapshot() {
  if [ "$(adb get-state 2>/dev/null)" = device ]; then s=android
  elif $SSH true 2>/dev/null; then s=linux
  else echo "no phone over adb or ssh" >&2; return 1; fi
  f=$OUT/$(date +%Y%m%d-%H%M%S)-$s.txt
  $s > "$f" 2>&1
  echo "$f"
}

[ $# -eq 0 ] && { snapshot; exit; }
while :; do snapshot; /usr/bin/sleep "$1"; done
