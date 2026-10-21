#!/usr/bin/env bash
# Prepare a checked-out OpenWrt tree for the build:
#   1. append the custom feeds and run feeds update/install
#   2. remove recursive dependency packages & restore missing core libs
#   3. assemble .config from the device config, run defconfig
#   4. disable bundling of custom feeds into the image
#   5. layer overlay files: device -> device/variant (most specific wins)

set -euo pipefail

# shellcheck source=scripts/lib/log.sh
source "$(dirname -- "$0")/lib/log.sh"

: "${OPENWRT_DIR:?OPENWRT_DIR required}"
: "${BUILDER_REPO:?BUILDER_REPO required}"
: "${VARIANT:?VARIANT required}"
: "${DEVICE:?DEVICE required}"

FEEDS="${FEEDS:-}"
DEVICE_DIR="$BUILDER_REPO/devices/$DEVICE"

[[ -f "$DEVICE_DIR/config" ]] || log::die "$DEVICE_DIR/config not found"

cd "$OPENWRT_DIR"

# 1. Configure feeds.
[[ -f feeds.conf ]] || cp feeds.conf.default feeds.conf

log::info "Disabling broken third-party feeds (video) to prevent Kconfig recursion"
sed -i '/video/d' feeds.conf || true

if [[ -n "$FEEDS" ]]; then
  log::info "Appending custom feeds:"
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    log::info "  $line"
    grep -qxF "$line" feeds.conf || echo "$line" >>feeds.conf
  done <<<"$FEEDS"
fi

log::info "Updating all feeds"
./scripts/feeds update -a

# 1a. Remove broken packages causing Kconfig recursive dependency errors
log::info "Removing recursive dependency packages (squeezelite, qt5base)"
rm -rf feeds/obsy/squeezelite package/feeds/obsy/squeezelite
rm -rf feeds/video/frameworks/qt5/qt5base package/feeds/video/qt5base

# 1b. Ensure libffi exists (moved from feeds/packages to core in newer OpenWrt)
if [[ ! -d "package/libs/libffi" && ! -d "feeds/packages/libs/libffi" ]]; then
  log::info "Restoring missing package/libs/libffi from upstream openwrt/main"
  tmp_libffi="$(mktemp -d)"
  git clone --depth 1 --filter=blob:none --sparse https://github.com/openwrt/openwrt.git "$tmp_libffi"
  git -C "$tmp_libffi" sparse-checkout set package/libs/libffi
  cp -a "$tmp_libffi/package/libs/libffi" package/libs/libffi
  rm -rf "$tmp_libffi"
fi

# 1c. Patch glib2-gobject Makefile for explicit +libffi dependency
if [[ -f "feeds/packages/libs/glib2/Makefile" ]]; then
  log::info "Ensuring glib2-gobject has +libffi dependency"
  sed -i '/^define Package\/glib2-gobject$/,/^endef$/ { /DEPENDS:=/ { /+libffi/! s/DEPENDS:=.*/& +libffi/ } }' \
    feeds/packages/libs/glib2/Makefile
fi

# 1d. Apply local patches to feed packages (patches/feeds/*/*.patch) BEFORE feeds install
shopt -s nullglob
for p in "$BUILDER_REPO"/patches/feeds/*/*.patch; do
  feed="feeds/$(basename "$(dirname "$p")")"
  if patch -p1 -d "$feed" --dry-run --forward < "$p" >/dev/null 2>&1; then
    log::info "Patching $feed with $(basename "$p")"
    patch -p1 -d "$feed" --forward < "$p"
  elif patch -p1 -d "$feed" --dry-run --reverse < "$p" >/dev/null 2>&1; then
    log::info "Skipping $(basename "$p") (already applied)"
  else
    log::die "$(basename "$p") does not apply to $feed"
  fi
done
shopt -u nullglob

# 1e. Install all feeds cleanly after patching and cleanup
log::info "Installing all feeds"
rm -rf tmp
./scripts/feeds install -a -f

# 2. Assemble .config from the device config, then resolve.
log::info "Assembling .config from devices/$DEVICE/config"
cp "$DEVICE_DIR/config" .config
make defconfig

# 2b. Verify defconfig honoured the device config.
log::info "Verifying defconfig kept the requested symbols"
dropped=()
while IFS= read -r req; do
  grep -qxF "$req" .config || dropped+=("$req")
done < <(grep -E '^CONFIG_[A-Za-z0-9_-]+=' "$DEVICE_DIR/config" | grep -vE '=n$')

if ((${#dropped[@]})); then
  log::error "defconfig dropped ${#dropped[@]} requested symbol(s) from devices/$DEVICE/config:"
  printf '  %s\n' "${dropped[@]}" >&2
  log::die "add the missing dependency or remove the line - do not ship a silently reduced image"
fi

# 3. Disable bundling of custom feeds into the image.
if [[ -n "$FEEDS" ]]; then
  log::info "Disabling CONFIG_FEED_<custom> entries"
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "$line" ]] && continue
    feed_name="$(awk '{print $2}' <<<"$line")"
    sed -i "s/^CONFIG_FEED_${feed_name}=.*/# CONFIG_FEED_${feed_name} is not set/" .config || true
  done <<<"$FEEDS"
fi
sed -i 's/^CONFIG_FEED_luci_extra=.*/# CONFIG_FEED_luci_extra is not set/' .config || true

# 4. Layer overlay files: device -> device/variant (most specific wins).
log::info "Applying overlay files"
mkdir -p files
for src in "$DEVICE_DIR/files" "$DEVICE_DIR/files.$VARIANT"; do
  if [[ -d "$src" ]]; then
    log::info "  $src"
    rsync -a "$src/" files/
  fi
done

# Lock down sshd_config if shipped.
if [[ -f files/etc/ssh/sshd_config ]]; then
  chmod 0600 files/etc/ssh/sshd_config
fi

log::info "Build environment ready for variant '$VARIANT' on device '$DEVICE'."