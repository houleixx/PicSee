#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/PicSee.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/Images/picsee_icon.png"
ICON_TIFF="$ROOT_DIR/build/AppIcon.tiff"
ICON_ICNS="$ROOT_DIR/build/AppIcon.icns"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/PicSee" "$MACOS_DIR/PicSee"

if [ ! -f "$ICON_SOURCE" ]; then
  echo "Missing icon source: $ICON_SOURCE" >&2
  exit 1
fi

sips -s format tiff "$ICON_SOURCE" --out "$ICON_TIFF" >/dev/null
tiff2icns "$ICON_TIFF" "$ICON_ICNS"
cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
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
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
