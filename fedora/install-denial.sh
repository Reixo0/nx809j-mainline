#!/bin/bash
# Install Denial, Phonewave's services and Denial's apps from a build of
# scripts/build-denial.sh against a Fedora sysroot, laid out as the Arch
# packages (archlinux/{denial,phonewave,denial-apps}-nx809j) lay them out.
# Until they are RPMs (phase 6 of the Fedora switch), files go straight in.
#
#   fedora/install-denial.sh STAGE [DESTDIR]
#     STAGE    build-denial.sh's output (STAGE=...), with denial/, phonewave/
#              and apps/ in it
#     DESTDIR  root to install into (default /); run as root
set -euo pipefail
# The build belongs to the user who copied it: copies must not keep its owner
cp_tree() { cp -dR --preserve=mode,timestamps "$@"; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
A=$ROOT/archlinux
ST=$(realpath "${1:?usage: $0 STAGE [DESTDIR]}")
D=${2:-}
[[ -d $ST/denial && -d $ST/phonewave && -d $ST/apps ]] || { echo "no build in $ST" >&2; exit 1; }

# Denial (as archlinux/denial-nx809j)
s=$ST/denial
install -d "$D/usr/lib/denial" "$D/usr/bin"
rm -rf "$D/usr/lib/denial/"{native,shell,settings,polkit}
cp_tree "$s"/{native,shell,settings,polkit,source-commit} "$D/usr/lib/denial/"
ln -sfn ../lib/denial/settings/denial-settings "$D/usr/bin/denial-settings"
for b in denialctl denial-portal denial-polkit-agent; do
  ln -sfn "../lib/denial/native/$b" "$D/usr/bin/$b"
done
install -Dm644 "$s/portal/denial-polkit-agent.service" "$D/usr/lib/systemd/user/denial-polkit-agent.service"
install -Dm644 "$s/portal/denial-portal.service" "$D/usr/lib/systemd/user/denial-portal.service"
install -Dm644 "$s/portal/denial-portals.conf" "$D/usr/share/xdg-desktop-portal/denial-portals.conf"
install -Dm644 "$s/portal/denial.portal" "$D/usr/share/xdg-desktop-portal/portals/denial.portal"
install -Dm644 "$s/portal/org.freedesktop.impl.portal.desktop.denial.service" \
  "$D/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service"
[[ -e $D/etc/xdg/xdg-desktop-portal-wlr/Denial ]] ||
  install -Dm644 "$s/portal/xdg-desktop-portal-wlr-Denial" "$D/etc/xdg/xdg-desktop-portal-wlr/Denial"
p=$A/denial-nx809j
install -Dm644 "$p/nx809j-denial.service" "$D/usr/lib/systemd/system/nx809j-denial.service"
install -Dm644 "$p/nx809j-denial.tmpfiles" "$D/usr/lib/tmpfiles.d/nx809j-denial.conf"
install -Dm644 "$p/outputs.conf" "$D/usr/share/nx809j/outputs.conf"
install -Dm644 "$p/denial-session.target" "$D/usr/lib/systemd/user/denial-session.target"
install -Dm644 "$p/dev.denial.Settings.desktop" "$D/usr/share/applications/dev.denial.Settings.desktop"

# Phonewave (as archlinux/phonewave-nx809j): its services start at boot
cp_tree "$ST/phonewave/usr" "$D/"
for f in $(cd "$ST/phonewave" && find etc -type f); do
  [[ -e $D/$f ]] || install -Dm644 "$ST/phonewave/$f" "$D/$f"  # keep edited configs
done
install -Dm644 "$A/phonewave-nx809j/nx809j-sensors-hexagonrpcd.service" \
  "$D/usr/lib/systemd/system/nx809j-sensors-hexagonrpcd.service"
w=$D/usr/lib/systemd/system/multi-user.target.wants
install -d "$w"
for u in hapticd steinerd braun dmail nx809j-sensors-hexagonrpcd; do
  ln -sfn "../$u.service" "$w/$u.service"
done
w=$D/usr/lib/systemd/user/default.target.wants
install -d "$w"
for u in callaudio braun-loopback; do ln -sfn "../$u.service" "$w/$u.service"; done

# Denial's apps (as archlinux/denial-apps-nx809j)
cp_tree "$ST/apps/usr" "$D/"
w=$D/usr/lib/systemd/user/graphical-session.target.wants
install -d "$w"
for u in calls-ringer messages-notifier; do ln -sfn "../$u.service" "$w/$u.service"; done

if [[ -z $D ]]; then
  systemd-sysusers
  systemd-tmpfiles --create nx809j-denial.conf
  systemctl daemon-reload
fi
echo "installed from $ST into ${D:-/}"
