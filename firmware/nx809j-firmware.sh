#!/system/bin/sh
# Copy the NX809J firmware Linux needs out of Android, as root, into a Linux
# root filesystem. Nothing is downloaded and nothing is redistributed: every
# file comes from this phone's own Android, read-only.
#
#   su -c sh nx809j-firmware.sh [TARGET]
#
# TARGET (default: /dev/block/by-name/linux, the Linux root partition):
#   a block device    mounted, files installed under usr/lib/firmware
#   a directory       files installed under DIR/usr/lib/firmware
#   FILE.tar          an archive with usr/lib/firmware/... inside
#
# The source directories can be overridden (FW_IMAGE, FW_BT, FW_VENDOR, and
# SOCCP) to run it on a copy of these files.
set -eu

FW_IMAGE=${FW_IMAGE:-/vendor/firmware_mnt/image}
FW_BT=${FW_BT:-/vendor/bt_firmware/image}
FW_VENDOR=${FW_VENDOR:-/vendor/firmware}
SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null || true)
SOCCP=${SOCCP:-/vendor/soccp_firmware/image}
SOCCP_DEV=/dev/block/by-name/soccp$SLOT
TARGET=${1:-/dev/block/by-name/linux}

DEV=qcom/kaanapali/nubia/nx809j
WORK=${TMPDIR:-/data/local/tmp}/nx809j-firmware.$$
STAGE=$WORK/stage/usr/lib/firmware
mounts=

die() { echo "error: $*" >&2; exit 1; }
cleanup() {
  for m in $mounts; do umount "$m" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

[ -d "$FW_IMAGE" ] || die "$FW_IMAGE not found (is this the NX809J's Android?)"
mkdir -p "$STAGE/$DEV" "$STAGE/ath12k/PEACH/hw2.0" "$STAGE/qca" "$WORK/mnt"

# Little-endian unsigned integer of $3 bytes at offset $2 of file $1
u() { od -An -tu"$3" -j"$2" -N"$3" "$1" | tr -d ' '; }

# Rebuild one ELF from <name>.mdt (headers) and <name>.bNN (segments), like
# linux-msm's pil-squasher: each segment is written at its p_offset.
squash() {
  mdt=$FW_IMAGE/$1.mdt dst=$STAGE/$DEV/$1.mbn
  [ -f "$mdt" ] || die "$mdt is missing"
  [ "$(od -An -tx1 -N4 "$mdt" | tr -d ' ')" = 7f454c46 ] || die "$mdt is not an ELF"
  cp "$mdt" "$dst"
  if [ "$(u "$mdt" 4 1)" = 2 ]; then  # ELF64 (offsets below 4 GiB)
    phoff=$(u "$mdt" 32 4) phentsize=$(u "$mdt" 54 2) phnum=$(u "$mdt" 56 2) o=8 f=32
  else
    phoff=$(u "$mdt" 28 4) phentsize=$(u "$mdt" 42 2) phnum=$(u "$mdt" 44 2) o=4 f=16
  fi
  i=0
  while [ $i -lt "$phnum" ]; do
    ph=$((phoff + i * phentsize))
    off=$(u "$mdt" $((ph + o)) 4) size=$(u "$mdt" $((ph + f)) 4)
    seg=$FW_IMAGE/$1.b$(printf %02d $i)
    # Segments without a file (headers, hash) are already inside the .mdt
    if [ "$size" -gt 0 ] && [ -f "$seg" ]; then
      # Largest power of two (up to 64 KiB) dividing the offset, for dd
      bs=65536
      while [ $((off % bs)) -ne 0 ]; do bs=$((bs / 2)); done
      dd if="$seg" of="$dst" bs=$bs seek=$((off / bs)) conv=notrunc 2>/dev/null ||
        die "writing $seg"
    fi
    i=$((i + 1))
  done
}

echo "Collecting firmware"
for n in adsp adsp_dtb cdsp cdsp_dtb modem modem_dtb ipa_fws; do
  squash $n
done

# SoCCP lives in its own FAT partition. Android mounts it (SELinux then
# refuses a second mount of it); mount it ourselves only if it hasn't.
if [ -d "$SOCCP" ]; then
  src=$SOCCP
else
  [ -e "$SOCCP_DEV" ] || die "$SOCCP_DEV not found"
  mkdir -p "$WORK/soccp"
  mount -t vfat -o ro "$SOCCP_DEV" "$WORK/soccp" || die "can't mount $SOCCP_DEV"
  mounts="$WORK/soccp $mounts" src=$WORK/soccp/image
fi
cp "$src/soccp.mbn" "$src/soccp_dtb.mbn" "$STAGE/$DEV/"

# GPU zap shader (signed for this phone). The GPU microcode itself comes from
# linux-firmware: the phone's GMU doesn't answer mainline's bandwidth votes.
cp "$FW_VENDOR/gen80200_zap.mbn" "$STAGE/$DEV/"
# Speaker amplifiers' tuning
cp "$FW_VENDOR/aw882xx_acf.bin" "$STAGE/$DEV/aw88461_acf.bin"

# The modem loads these over tqftpserv from next to modem.mbn: its MBN
# configuration (modem_pr), OEM software (modem_oem) and their manifest
cp "$FW_IMAGE/modemr.jsn" "$STAGE/$DEV/"
cp -R "$FW_IMAGE/modem_pr" "$FW_IMAGE/modem_oem" "$STAGE/$DEV/"

# Wi-Fi (peach) under ath12k's names
for p in amss.bin:amss20.bin m3.bin:phy_ucode20.elf aux_ucode.bin:aux_ucode20.elf \
    board.bin:bdwlan.elf regdb.bin:regdb.bin qdss_trace_config.cfg:qdss_trace_config_v2.cfg; do
  cp "$FW_IMAGE/peach/${p#*:}" "$STAGE/ath12k/PEACH/hw2.0/${p%%:*}"
done

# Bluetooth (Brahma): rampatch and board NVM files
cp "$FW_BT/brhbtfw20.mbn" "$FW_BT"/brhbtnv20.* "$STAGE/qca/"

# Where these came from, for when Android is updated
{
  echo "Copied from Android by nx809j-firmware.sh on $(date -u '+%Y-%m-%d %H:%M UTC')"
  # The vendor build, not the system one: custom ROMs may spoof the latter
  echo "vendor: $(getprop ro.vendor.build.fingerprint 2>/dev/null || echo unknown)"
  echo "modem: $(getprop gsm.version.baseband 2>/dev/null || echo unknown)"
} > "$STAGE/$DEV/SOURCE"
chmod -R u=rwX,go=rX "$WORK/stage"
echo "  $(find "$STAGE" -type f | wc -l | tr -d ' ') files, $(du -sk "$STAGE" | cut -f1) KiB"

install_into() {
  [ -d "$1/usr/lib" ] || die "$1 doesn't look like a Linux root (no usr/lib)"
  mkdir -p "$1/usr/lib/firmware"
  (cd "$WORK/stage" && tar cf - usr) | (cd "$1" && tar xf - --no-same-owner) ||
    die "copying into $1"
  echo "Installed into $1/usr/lib/firmware"
}

case $TARGET in
  *.tar)
    (cd "$WORK/stage" && tar cf - usr) > "$TARGET" || die "writing $TARGET"
    echo "Wrote $TARGET" ;;
  *)
    if [ -b "$TARGET" ]; then
      mkdir -p "$WORK/root"
      mount "$TARGET" "$WORK/root" || die "can't mount $TARGET (is Linux installed?)"
      mounts="$WORK/root $mounts"
      install_into "$WORK/root"
      sync
    elif [ -d "$TARGET" ]; then
      install_into "$TARGET"
    else
      die "$TARGET is not a block device, a directory or a .tar file"
    fi ;;
esac
echo "Done."
