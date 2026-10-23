#!/system/bin/sh
# Runs on the phone: print "<name> <MiB> <blockdev>" for every by-name partition.
for p in /dev/block/by-name/*; do
  t=$(readlink -f "$p"); s=$(cat /sys/class/block/${t##*/}/size 2>/dev/null)
  echo "${p##*/} $((s/2048)) $t"
done
