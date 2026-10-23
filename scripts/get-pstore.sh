#!/usr/bin/env bash
# After a failed boot, back in Android: save the previous kernel's console log
# (ramoops @ 0xe2000000) and say whether it came from our mainline kernel.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/out/pstore"
f="$ROOT/out/pstore/$(date +%Y%m%d-%H%M%S).txt"
adb wait-for-device
adb exec-out su -c 'cat /sys/fs/pstore/console-ramoops* 2>/dev/null' > "$f"
if [[ ! -s $f ]]; then
  echo "no pstore console log (kernel never reached ramoops, or RAM was lost)"; rm -f "$f"; exit 1
fi
echo "saved $f"
if grep -aq -- '-nx809j' "$f"; then
  echo ">> log is from the MAINLINE kernel; last lines:"
  tail -n 40 "$f"
else
  echo ">> log is from an Android kernel ($(grep -a -m1 -o 'Linux version [^ ]*' "$f" || echo 'version line not kept')): mainline never got to ramoops"
fi
