#!/usr/bin/env bash
# Copy the kernel modules from scripts/build.sh (out/modules) into the running
# phone's rootfs over SSH and run depmod. The kernel itself comes from boot_a,
# so the modules must be from the same build as the flashed boot image.
#
# Usage: scripts/install-modules.sh [user@host]   (default reixo@172.16.42.1)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOST=${1:-reixo@172.16.42.1}
REL=$(cat "$ROOT/out/kernel/include/config/kernel.release")
SRC=$ROOT/out/modules/lib/modules/$REL
[[ -d $SRC ]] || { echo "no modules for $REL; run scripts/build.sh modules" >&2; exit 1; }

running=$(ssh "$HOST" uname -r)
[[ $running == "$REL" ]] || echo "note: phone runs $running, installing $REL"
# On the known-good boot entry the saved modules are mounted over this
# directory, and replacing it would overwrite them
if ssh "$HOST" mountpoint -q "/usr/lib/modules/$REL"; then
  echo "the phone runs the known-good entry; reboot into the default one first" >&2
  exit 1
fi

# Replace the whole directory so modules dropped from the config don't linger
tar -C "$SRC/.." --owner=0 --group=0 -czf - "$REL" | ssh "$HOST" "
  set -e
  sudo rm -rf /usr/lib/modules/$REL.new
  sudo mkdir -p /usr/lib/modules/$REL.new
  sudo tar -xzf - -C /usr/lib/modules/$REL.new --strip-components=1
  sudo rm -rf /usr/lib/modules/$REL
  sudo mv /usr/lib/modules/$REL.new /usr/lib/modules/$REL
  sudo depmod $REL
  echo \"installed \$(find /usr/lib/modules/$REL -name '*.ko*' | wc -l) modules for $REL\""
