#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUILD_SCRIPT="$ROOT_DIR/Scripts/build-app.sh"
APP_DIR="$ROOT_DIR/build/PicSee.app"
DMG_STAGE_DIR="$ROOT_DIR/build/dmg-stage"
DMG_DIR="$ROOT_DIR/build/dmg"
LEGACY_PKG_ROOT_DIR="$ROOT_DIR/build/pkg-root"
APP_VERSION="${PICSEE_VERSION:-0.2.24}"
APP_BUILD_NUMBER="${PICSEE_BUILD_NUMBER:-${APP_VERSION##*.}}"
DMG_NAME="PicSee-${APP_VERSION}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"
MODULE_CACHE_DIR="$ROOT_DIR/build/module-cache"
CLANG_CACHE_DIR="$MODULE_CACHE_DIR/clang"
SWIFT_CACHE_DIR="$MODULE_CACHE_DIR/swift"

cleanup_stage_dir() {
  rm -rf "$DMG_STAGE_DIR"
}

cd "$ROOT_DIR"
trap cleanup_stage_dir EXIT

rm -rf "$LEGACY_PKG_ROOT_DIR"
mkdir -p "$CLANG_CACHE_DIR" "$SWIFT_CACHE_DIR"

env \
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
  SWIFT_MODULECACHE_PATH="$SWIFT_CACHE_DIR" \
  PICSEE_VERSION="$APP_VERSION" \
  PICSEE_BUILD_NUMBER="$APP_BUILD_NUMBER" \
  PICSEE_SKIP_LOCAL_INSTALL="${PICSEE_SKIP_LOCAL_INSTALL:-1}" \
  "$APP_BUILD_SCRIPT"

if [ ! -d "$APP_DIR" ]; then
  echo "Missing app bundle: $APP_DIR" >&2
  exit 1
fi

rm -rf "$DMG_STAGE_DIR" "$DMG_DIR"
mkdir -p "$DMG_STAGE_DIR" "$DMG_DIR"

ditto "$APP_DIR" "$DMG_STAGE_DIR/PicSee.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

hdiutil create \
  -volname "PicSee" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Built DMG $DMG_PATH"
