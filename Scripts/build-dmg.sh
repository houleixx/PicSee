#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUILD_SCRIPT="$ROOT_DIR/Scripts/build-app.sh"
APP_DIR="$ROOT_DIR/build/PicSee.app"
DMG_STAGE_DIR="$ROOT_DIR/build/dmg-stage"
DMG_DIR="$ROOT_DIR/build/dmg"
LEGACY_PKG_ROOT_DIR="$ROOT_DIR/build/pkg-root"
APP_VERSION="${PICSEE_VERSION:-0.2.53}"
APP_BUILD_NUMBER="${PICSEE_BUILD_NUMBER:-${APP_VERSION##*.}}"
CODESIGN_IDENTITY="${PICSEE_CODESIGN_IDENTITY:--}"
DMG_NAME="PicSee-${APP_VERSION}.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"
MODULE_CACHE_DIR="$ROOT_DIR/build/module-cache"
CLANG_CACHE_DIR="$MODULE_CACHE_DIR/clang"
SWIFT_CACHE_DIR="$MODULE_CACHE_DIR/swift"
DMG_ASSETS_DIR="$ROOT_DIR/build/dmg-assets"
DMG_TOOLS_DIR="$ROOT_DIR/build/dmg-tools"
DMGBUILD_BIN="${PICSEE_DMGBUILD:-$DMG_TOOLS_DIR/bin/dmgbuild}"

cleanup_stage_dir() {
  rm -rf "$DMG_STAGE_DIR"
}

cd "$ROOT_DIR"
trap cleanup_stage_dir EXIT

rm -rf "$LEGACY_PKG_ROOT_DIR"
mkdir -p "$CLANG_CACHE_DIR" "$SWIFT_CACHE_DIR"

if [ -z "${PICSEE_DMGBUILD:-}" ]; then
  if [ ! -x "$DMG_TOOLS_DIR/bin/python" ]; then
    python3 -m venv "$DMG_TOOLS_DIR"
  fi
  "$DMG_TOOLS_DIR/bin/python" -m pip install --disable-pip-version-check \
    -r "$ROOT_DIR/Scripts/dmg-requirements.txt"
fi

swift -module-cache-path "$SWIFT_CACHE_DIR" \
  "$ROOT_DIR/Scripts/dmg-background.swift" "$DMG_ASSETS_DIR"

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

rm -rf "$DMG_STAGE_DIR"
mkdir -p "$DMG_DIR"

"$DMGBUILD_BIN" -s "$ROOT_DIR/Scripts/dmg-settings.py" \
  -D "app=$APP_DIR" -D "background=$DMG_ASSETS_DIR/background.png" \
  "PicSee" "$DMG_PATH"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH" >/dev/null
  echo "Signed DMG $DMG_PATH ($CODESIGN_IDENTITY)"
fi

echo "Built DMG $DMG_PATH"
