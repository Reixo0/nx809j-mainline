#!/usr/bin/env bash
# Persistently let the phone (172.16.42.1, USB link) reach the internet
# through this PC, with ufw. Run with sudo; safe to run again.
#
#  - /etc/sysctl.d/90-nx809j-usb-nat.conf: IPv4 forwarding on
#  - /etc/ufw/before.rules: NAT (masquerade) for 172.16.42.0/24 only
#  - ufw route rule: forward traffic coming from 172.16.42.0/24 only
#  - ufw rule for the NBD rootfs server (scripts/nbd-root.sh)
#
# Undo: remove the sysctl file and the "nx809j" block in before.rules,
#       `ufw delete` the two rules, then `ufw reload`.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
NET=172.16.42.0/24
RULES=/etc/ufw/before.rules
BEGIN='# BEGIN nx809j USB NAT'
END='# END nx809j USB NAT'

echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/90-nx809j-usb-nat.conf
sysctl -q -p /etc/sysctl.d/90-nx809j-usb-nat.conf

if ! grep -qF "$BEGIN" "$RULES"; then
  cp "$RULES" "$RULES.bak-nx809j"
  # The nat table has to come before ufw's *filter section
  tmp=$(mktemp)
  {
    echo "$BEGIN"
    echo '*nat'
    echo ':POSTROUTING ACCEPT [0:0]'
    echo "-A POSTROUTING -s $NET ! -d $NET -j MASQUERADE"
    echo 'COMMIT'
    echo "$END"
    echo
    cat "$RULES"
  } > "$tmp"
  install -m 640 "$tmp" "$RULES"
  rm -f "$tmp"
  echo "added NAT block to $RULES (backup: $RULES.bak-nx809j)"
fi

ufw route allow from "$NET" comment 'nx809j USB NAT'
ufw allow in from 172.16.42.1 to 172.16.42.2 port 10809 proto tcp comment 'nx809j NBD rootfs'
ufw reload
echo "done: the phone can use 172.16.42.2 as its gateway"
