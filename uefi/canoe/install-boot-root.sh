#!/system/bin/sh
# Creates Canoe's boot root (persist/efisp.fat) on the NX809J from a rooted
# Android shell, with Android in Mode 2 (existing profile) and the ESP
# dispatcher for Linux. Plan only unless --apply. Run as root from the
# bundle directory (see uefi/README.md, "Dual boot with Canoe"):
#   bin/canoe-provision, bin/canoe-bootmgr   (Canoe one-shot package)
#   staged/boot.efi{,.gm2p,.tzmap}           (orange screen skipped)
#   staged-orig/boot.efi{,.gm2p,.tzmap}      (as canoe-image made it)
#   tools/*.efi                              (Canoe EFI tools)
#   nx809j/dispatch.efi, nx809j/mu/MU.fd
# Android's kernel refuses raw writes to efisp, so BDS.efi is flashed from
# Canoe's own Super Fastboot afterwards. Needs SELinux permissive for the
# loop mount (setenforce 0, then 1).
set -eu
R=$(cd "$(dirname "$0")" && pwd)
P=/mnt/vendor/persist
M=$R/mnt
die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ ! -e "$P/efisp.fat" ] || die "$P/efisp.fat already exists"
"$R/bin/canoe-provision" inspect --persist-directory "$P" || true
echo "Plan: create $P/efisp.fat with boot_a.efi and boot_backup.efi (Mode 2),"
echo "      entries android-a (default), linux, android-backup"
[ "${1:-}" = --apply ] || { echo "Plan only: nothing written."; exit 0; }
[ "$(getenforce)" != Enforcing ] || die "SELinux is Enforcing (setenforce 0 first)"

"$R/bin/canoe-provision" create --persist-directory "$P"
LOOP=$(losetup -f)
losetup "$LOOP" "$P/efisp.fat"
mkdir -p "$M"
mount -t vfat -o rw "$LOOP" "$M"
B="$R/bin/canoe-bootmgr --boot-root $M"
$B loader install --slot a --from "$R/staged"
$B loader install --slot backup --from "$R/staged-orig"
mkdir -p "$M/tools" "$M/nx809j/mu"
cp "$R"/tools/*.efi "$M/tools/"
cp "$R/nx809j/dispatch.efi" "$M/nx809j/"
cp "$R/nx809j/mu/MU.fd" "$M/nx809j/mu/"
$B entry set --id android-a --title Android --image boot_a.efi --role active \
	--mode 2 --devinfo-repair never --default
$B entry set --id linux --title "Arch Linux" --image nx809j/dispatch.efi
$B entry set --id android-backup --title "Android (unpatched)" \
	--image boot_backup.efi --role backup --mode 2
$B config set-policy --menu-mode silent --key-window-ms 1200
$B config show
cmp "$R/nx809j/mu/MU.fd" "$M/nx809j/mu/MU.fd"
cmp "$R/staged/boot.efi.gm2p" "$M/boot_a.efi.gm2p"
sync
umount "$M"
losetup -d "$LOOP" 2>/dev/null || true
echo "Boot root ready. Next: flash BDS.efi to efisp from Canoe Super Fastboot."
