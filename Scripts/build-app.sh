#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/PicSee.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Images/picsee_icon.png"
ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
ICON_ICNS="$ROOT_DIR/build/AppIcon.icns"

cd "$ROOT_DIR"
ARM64_BUILD_DIR="$ROOT_DIR/.build-arm64"
X64_BUILD_DIR="$ROOT_DIR/.build-x86_64"
APP_VERSION="${PICSEE_VERSION:-0.2.8}"
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

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

rm -f "$ICON_ICNS"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
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
    <string>13.0</string>
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
                <string>public.image</string>
                <string>public.jpeg</string>
                <string>public.png</string>
                <string>com.compuserve.gif</string>
                <string>public.heic</string>
                <string>public.tiff</string>
                <string>com.microsoft.bmp</string>
                <string>org.webmproject.webp</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>jpg</string>
                <string>jpeg</string>
                <string>png</string>
                <string>gif</string>
                <string>heic</string>
                <string>tif</string>
                <string>tiff</string>
                <string>bmp</string>
                <string>webp</string>
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
