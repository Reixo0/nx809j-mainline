#!/usr/bin/env bash
# Cross-build Denial, Phonewave's services and Denial's apps on an x86-64 host,
# with the phone's own libraries as the sysroot. Leaves what scripts/arch-pkgs.sh
# packs in $DENIAL_BUILD/stage/{denial,phonewave,apps}.
#
#   DENIAL_BUILD=dir scripts/build-denial.sh   (default: ~/denial-build)
#
# Needs: $DENIAL_BUILD/sysroot, a copy of a phone's /usr with
#   seatd libinput wayland libxkbcommon libdrm mesa gtk3 fontconfig installed,
#   and a "lib -> usr/lib" link; clang, lld, rustup with the aarch64 target.
# Clones into $DENIAL_BUILD what isn't there; the first run builds the Flutter
# engine twice (about an hour on 20 cores, 30 GB in ~/.cache/denial).
set -euo pipefail
W=$(realpath "${DENIAL_BUILD:-$HOME/denial-build}")
S=$W/sysroot
[[ -d $S/usr/lib/pkgconfig ]] || { echo "no sysroot in $S" >&2; exit 1; }
TARGET=aarch64-unknown-linux-gnu
JOBS=${JOBS:-$(($(nproc) * 4 / 5))}
OUT=$W/work; CC_DIR=$OUT/cc
mkdir -p "$OUT" "$CC_DIR"

clone() {  # name branch
  [[ -d $W/$1 ]] || git clone --branch "$2" "https://github.com/denialwm/$1.git" "$W/$1"
}
clone denial dev; clone phonewave main; clone denial-apps main; clone gpui-touch main

export DENIAL_BUILD_JOBS=$JOBS
export DENIAL_USER_CACHE=$HOME/.cache/denial
export DENIAL_PC_DEPENDENCY_ROOT=$DENIAL_USER_CACHE/pc-dependencies
export DENIAL_FLUTTER_ENGINE_CACHE_ROOT=$DENIAL_USER_CACHE/flutter-engine
ENGINE_SRC=$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/checkout/engine/src
HOST_OUT=$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/build/out/denial_host_release
ARM_ROOT=$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/build-arm64
ARM_NAME=denial_linux_arm64_release
ARM_OUT=$ARM_ROOT/out/$ARM_NAME
FLUTTER=$DENIAL_PC_DEPENDENCY_ROOT/flutter/bin/flutter

# Flutter engine: the host's and the phone's
(cd "$W/denial"
 [[ -x $FLUTTER ]] || tools/denial-pc bootstrap
 tools/denial-flutter-engine prepare-app-build)
rustup target add "$TARGET"
(cd "$ENGINE_SRC"
 tools=$ENGINE_SRC/flutter/third_party/depot_tools
 export PATH=$tools/.cipd_bin:$tools:$PATH DEPOT_TOOLS_UPDATE=0
 export VPYTHON_VIRTUALENV_ROOT=$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/vpython
 [[ -f $ARM_OUT/args.gn ]] || ./flutter/tools/gn --runtime-mode=release --linux --linux-cpu=arm64 \
   --enable-fontconfig --out-dir="$ARM_ROOT" --target-dir=$ARM_NAME
 /usr/bin/ninja -C "$ARM_OUT" -j "$JOBS" libflutter_engine.so clang_x64/gen_snapshot flutter_patched_sdk)

# Flutter applications, compiled for the phone by the host's tools
VIEW=$OUT/engine-view
rm -rf "$VIEW"; mkdir -p "$VIEW/out/$ARM_NAME"
ln -s "$ENGINE_SRC/flutter" "$VIEW/flutter"
ln -s "$HOST_OUT" "$VIEW/out/denial_host_release"
for p in "$ARM_OUT"/*; do
  [[ ${p##*/} == gen_snapshot ]] || ln -s "$p" "$VIEW/out/$ARM_NAME/${p##*/}"
done
ln -s "$ARM_OUT/clang_x64/gen_snapshot" "$VIEW/out/$ARM_NAME/gen_snapshot"
assemble() {  # application directory, output
  (cd "$W/denial/$1"
   "$FLUTTER" pub get --enforce-lockfile
   "$FLUTTER" assemble --local-engine-src-path="$VIEW" --local-engine=$ARM_NAME \
     --local-engine-host=denial_host_release --suppress-analytics --resource-pool-size="$JOBS" \
     --output="$2" -dTargetFile=lib/main.dart -dBuildMode=release -dTargetPlatform=linux-arm64 \
     -dDartObfuscation=false -dTrackWidgetCreation=true -dTreeShakeIcons=true \
     release_bundle_linux-arm64_assets)
}
assemble dart_shell "$OUT/shell-assembly"
assemble settings_app "$OUT/settings-assembly"

# Rust: clang and lld stand in for an aarch64 gcc
printf '#!/bin/sh\nexec clang --target=aarch64-linux-gnu --sysroot=%s -fuse-ld=lld "$@"\n' "$S" > "$CC_DIR/aarch64-linux-gnu-gcc"
printf '#!/bin/sh\nexec clang++ --target=aarch64-linux-gnu --sysroot=%s -fuse-ld=lld "$@"\n' "$S" > "$CC_DIR/aarch64-linux-gnu-g++"
printf '#!/bin/sh\nexec llvm-ar "$@"\n' > "$CC_DIR/aarch64-linux-gnu-ar"
chmod +x "$CC_DIR"/*
export PATH=$CC_DIR:$PATH
export PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_SYSROOT_DIR=$S
export PKG_CONFIG_LIBDIR=$S/usr/lib/pkgconfig:$S/usr/share/pkgconfig
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=-Wl,-rpath-link,$S/usr/lib"
export BINDGEN_EXTRA_CLANG_ARGS="--target=aarch64-linux-gnu --sysroot=$S"
export RUST_FONTCONFIG_DLOPEN=1
cross() {  # directory, cargo arguments
  (cd "$1"; shift; cargo build --release --locked --target "$TARGET" -j "$JOBS" "$@")
}
export CARGO_TARGET_DIR=$OUT/rust
D=$CARGO_TARGET_DIR/$TARGET/release
cross "$W/denial/compositor" --features flutter,ui-development --bin deniald --bin denialctl --bin denial-ui
cross "$W/denial/compositor" -p denial-portal
cross "$W/denial/native_app" --bin denial-app
export CARGO_TARGET_DIR=$OUT/pw-rust
PW=$CARGO_TARGET_DIR/$TARGET/release
for s in haptics/hapticd sensors/steinerd camera/braun; do cross "$W/phonewave/services/$s"; done
export CARGO_TARGET_DIR=$OUT/apps-rust
AP=$CARGO_TARGET_DIR/$TARGET/release
for a in camera sensors settings; do cross "$W/denial-apps/apps/$a"; done

# Stage what each package holds
ST=$W/stage; rm -rf "$ST"
bundle() {  # assembly, destination
  mkdir -p "$2/data/flutter_assets" "$2/lib"
  cp -a "$1/flutter_assets/." "$2/data/flutter_assets/"
  install -m755 "$1/lib/libapp.so" "$ARM_OUT/libflutter_engine.so" "$2/lib/"
  install -m644 "$ARM_OUT/icudtl.dat" "$2/data/"
}
n=$ST/denial; mkdir -p "$n/native"
install -m755 "$D"/{deniald,denialctl,denial-ui,denial-portal} "$n/native/"
bundle "$OUT/shell-assembly" "$n/shell"
bundle "$OUT/settings-assembly" "$n/settings"
install -m755 "$D/denial-app" "$n/settings/denial-settings"
git -C "$W/denial" rev-parse HEAD > "$n/source-commit"

n=$ST/phonewave; P=$W/phonewave/services; R=$W/phonewave/devices/nx809j/rootfs
mkdir -p "$n/usr/bin" "$n/usr/lib/systemd/system" "$n/usr/share/dbus-1/system-services" \
  "$n/usr/share/dbus-1/system.d" "$n/usr/lib/sysusers.d" "$n/usr/lib/udev/rules.d" \
  "$n/usr/share/braun/sensors" "$n/etc/braun" "$n/etc/hapticd"
install -m755 "$PW"/{hapticd,hapticctl,steinerd,steinerctl,braun,braunctl} "$n/usr/bin/"
for s in haptics/hapticd:hapticd sensors/steinerd:steinerd camera/braun:braun; do
  k=$P/${s%:*}/packaging; m=${s#*:}
  install -m644 "$k/$m.service" "$n/usr/lib/systemd/system/"
  install -m644 "$k/org.$m.service" "$n/usr/share/dbus-1/system-services/"
  install -m644 "$k/org.$m.conf" "$n/usr/share/dbus-1/system.d/"
done
install -m644 "$P/camera/braun/packaging/braun.sysusers" "$n/usr/lib/sysusers.d/braun.conf"
install -m644 "$P/camera/braun/sensors/"*.toml "$n/usr/share/braun/sensors/"
install -m644 "$R/etc/braun/"*.toml "$n/etc/braun/"
install -m644 "$R/etc/hapticd/config.json" "$n/etc/hapticd/"
install -m644 "$R/usr/lib/udev/rules.d/70-hapticd-aw86927-haptics.rules" "$n/usr/lib/udev/rules.d/"

n=$ST/apps; mkdir -p "$n/usr/bin" "$n/usr/share/applications" \
  "$n/usr/share/icons/hicolor/512x512/apps" "$n/usr/share/licenses/denial-apps-nx809j"
for a in camera:Camera:denial-camera sensors:Sensors:denial-sensors settings:Settings:denial-phone-settings; do
  IFS=: read -r d N b <<< "$a"
  install -m755 "$AP/$d" "$n/usr/bin/$b"
  sed "s|^Exec=.*|Exec=/usr/bin/$b|; s|^Name=Settings\$|Name=Phone Settings|" \
    "$W/denial-apps/apps/$d/org.denialwm.$N.desktop" > "$n/usr/share/applications/org.denialwm.$N.desktop"
  install -m644 "$W/denial-apps/apps/$d/org.denialwm.$N.png" "$n/usr/share/icons/hicolor/512x512/apps/"
done
install -m644 "$W/denial-apps/LICENSE.md" "$n/usr/share/licenses/denial-apps-nx809j/"

if find "$ST" -type f -perm /111 ! -name '*.toml' -exec file {} + | grep ELF | grep -v 'ARM aarch64'; then
  echo "not everything is aarch64" >&2; exit 1
fi
du -sh "$ST"/*
