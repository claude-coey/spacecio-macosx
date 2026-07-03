#!/bin/bash
# Builds "SpaceSIO Relay.app" and a drag-to-Applications DMG.
#
# Usage:
#   ./scripts/make-installer.sh
#
# Output: dist/SpaceSIO-Relay-<version>.dmg
#
# Signing: by default the app is ad-hoc signed (runs fine locally; downloaders
# must right-click → Open the first time). When you have an Apple Developer ID
# certificate, export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
# before running, then notarize the DMG:
#   xcrun notarytool submit dist/*.dmg --keychain-profile <profile> --wait
#   xcrun stapler staple dist/*.dmg

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="SpaceSIO Relay"
BUNDLE_ID="com.spacesio.relay"
VERSION="1.2"
BIN="SpaceSIORelay"
DIST="dist"

echo "▸ Building release binary…"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN_PATH=".build/apple/Products/Release/$BIN"
  echo "  universal (arm64 + x86_64)"
else
  echo "  universal build unavailable — building native arch"
  swift build -c release
  BIN_PATH=".build/release/$BIN"
fi

rm -rf "$DIST"
APP="$DIST/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN"

# SPM resource bundle (brand logo etc.) — Bundle.module finds it in
# Contents/Resources at runtime.
RES_BUNDLE="$(dirname "$BIN_PATH")/${BIN}_${BIN}.bundle"
if [ -d "$RES_BUNDLE" ]; then
  cp -R "$RES_BUNDLE" "$APP/Contents/Resources/"
  echo "  bundled resources: $(basename "$RES_BUNDLE")"
else
  echo "  WARNING: resource bundle not found at $RES_BUNDLE"
fi

echo "▸ Writing bundle Info.plist…"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$BIN</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>15.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSLocationUsageDescription</key>
	<string>Your station location is included in the signed confirmation sent back after each broadcast, so the network can map where signals went on air. You can use manual coordinates instead in Settings.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Your station location is included in the signed confirmation sent back after each broadcast, so the network can map where signals went on air. You can use manual coordinates instead in Settings.</string>
</dict>
</plist>
PLIST

echo "▸ Building AppIcon.icns…"
if [ -f assets/icon-1024.png ]; then
  ICONSET="$DIST/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" assets/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
else
  echo "  assets/icon-1024.png missing — skipping icon"
fi

echo "▸ Signing…"
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --deep --options runtime --sign "$DEVELOPER_ID" "$APP"
  echo "  signed with: $DEVELOPER_ID"
else
  codesign --force --deep --sign - "$APP"
  echo "  ad-hoc signed (set DEVELOPER_ID for distribution signing)"
fi

echo "▸ Creating DMG…"
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/SpaceSIO-Relay-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ Done: $DMG"
