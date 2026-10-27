#!/system/bin/sh
# Arms the Canoe boot manager's boot-once record for its "linux" entry
# (Mu-Silicium -> systemd-boot -> Linux) in the bootloader control block's
# command field (first 32 bytes of misc), then reboots. Canoe clears it
# before launching. A stale "bootonce-bootloader" is replaced, any other
# pending command is left alone.
misc=/dev/block/by-name/misc
cmd=$(head -c 32 $misc | tr -d '\000')
case $cmd in
'' | canoe-once:* | bootonce-bootloader) ;;
*) echo "misc already holds \"$cmd\", not touching it"; exit 1 ;;
esac
printf 'canoe-once:linux' | dd of=$misc bs=32 count=1 conv=sync,notrunc 2>/dev/null
sync
if [ "$(head -c 32 $misc | tr -d '\000')" != canoe-once:linux ]; then
	echo "writing the boot-once record failed"
	exit 1
fi
echo "Rebooting to Linux."
sleep 1
/system/bin/reboot
