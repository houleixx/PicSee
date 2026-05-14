#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/PicSee.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Images/picsee_icon.png"
ICON_WORK_DIR="$ROOT_DIR/build/icon-tiff"
ICON_TIFF="$ROOT_DIR/build/AppIcon.tiff"
ICON_ICNS="$ROOT_DIR/build/AppIcon.icns"

cd "$ROOT_DIR"
ARM64_BUILD_DIR="$ROOT_DIR/.build-arm64"
X64_BUILD_DIR="$ROOT_DIR/.build-x86_64"
APP_VERSION="${PICSEE_VERSION:-0.2.1}"
APP_BUILD_NUMBER="${PICSEE_BUILD_NUMBER:-1}"
SKIP_LOCAL_INSTALL="${PICSEE_SKIP_LOCAL_INSTALL:-0}"

swift build -c release --arch arm64 --build-path "$ARM64_BUILD_DIR"
swift build -c release --arch x86_64 --build-path "$X64_BUILD_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
lipo -create \
  "$ARM64_BUILD_DIR/release/PicSee" \
  "$X64_BUILD_DIR/release/PicSee" \
  -output "$MACOS_DIR/PicSee"

if [ ! -f "$ICON_SOURCE" ]; then
  echo "Missing icon source: $ICON_SOURCE" >&2
  exit 1
fi

rm -rf "$ICON_WORK_DIR"
mkdir -p "$ICON_WORK_DIR"

for size in 16 32 48 128 256 512 1024; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICON_WORK_DIR/icon-${size}.tiff" >/dev/null
done

tiffutil -cat \
  "$ICON_WORK_DIR/icon-16.tiff" \
  "$ICON_WORK_DIR/icon-32.tiff" \
  "$ICON_WORK_DIR/icon-48.tiff" \
  "$ICON_WORK_DIR/icon-128.tiff" \
  "$ICON_WORK_DIR/icon-256.tiff" \
  "$ICON_WORK_DIR/icon-512.tiff" \
  "$ICON_WORK_DIR/icon-1024.tiff" \
  -out "$ICON_TIFF"

rm -f "$ICON_ICNS"
tiff2icns "$ICON_TIFF"
cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PicSee</string>
    <key>CFBundleIdentifier</key>
    <string>local.picsee.viewer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PicSee</string>
    <key>CFBundleDisplayName</key>
    <string>PicSee</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_NUMBER}</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.jpeg</string>
                <string>public.png</string>
                <string>com.compuserve.gif</string>
                <string>public.heic</string>
                <string>public.tiff</string>
                <string>com.microsoft.bmp</string>
                <string>org.webmproject.webp</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"

# 用稳定标识符做 ad-hoc 重新签名，让 macOS 隐私子系统(TCC)把每次重建的 app 视为同一个，
# 用户授予「桌面/下载」等文件夹访问权后不会每次重新打包都再问。
codesign --force --deep --sign - \
  --identifier "local.picsee.viewer" \
  --options runtime \
  --timestamp=none \
  "$APP_DIR" >/dev/null
echo "Signed $APP_DIR (ad-hoc, stable identifier)"

if [ "$SKIP_LOCAL_INSTALL" != "1" ]; then
  # 同步到用户「应用程序」文件夹（与 ~/Applications 同一路径，例如 /Users/holly/Applications）
  USER_APPS_DIR="${HOME}/Applications"
  mkdir -p "$USER_APPS_DIR"
  ditto "$APP_DIR" "$USER_APPS_DIR/PicSee.app"
  echo "Installed $USER_APPS_DIR/PicSee.app"
fi
