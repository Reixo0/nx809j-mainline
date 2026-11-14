#!/bin/bash
# postmarketOS's mobile Firefox configuration (as archlinux/mobile-config-firefox),
# for Fedora's Firefox, which lives in /usr/lib64/firefox.
# Usage: sudo fedora/install-mobile-config-firefox.sh [DESTDIR]
set -euo pipefail
VER=5.5.2
SUM=3b69740272619d74c7bdada4ffe6284c40c7535821023afc178f56d55b8dd9ec
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT
curl -sfL -o "$B/m.tar.gz" \
  "https://gitlab.postmarketos.org/postmarketOS/mobile-config-firefox/-/archive/$VER/mobile-config-firefox-$VER.tar.gz"
echo "$SUM  $B/m.tar.gz" | sha256sum -c --quiet
tar -xzf "$B/m.tar.gz" -C "$B"
make -C "$B/mobile-config-firefox-$VER" install DESTDIR="${1:-}" FIREFOX_DIR=/usr/lib64/firefox
