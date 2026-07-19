#!/usr/bin/env bash
# Build, sign, notarize and package YTDLBridge into a DMG.
#
# Prerequisites:
#   - Apple Developer Program membership.
#   - "Developer ID Application" certificate installed in the login keychain.
#   - Notary credentials stored in the keychain under profile name "AC_NOTARY":
#       xcrun notarytool store-credentials AC_NOTARY \
#         --apple-id "you@example.com" \
#         --team-id  "XXXXXXXXXX" \
#         --password "app-specific-password"
#   - Environment variables (or edit the defaults):
#       TEAM_ID          Apple team ID (10 chars)
#       NOTARY_PROFILE   Keychain profile name (default: AC_NOTARY)

set -euo pipefail

cd "$(dirname "$0")/.."

APP=YTDLBridge
SCHEME="${SCHEME:-$APP}"
TEAM_ID="${TEAM_ID:?TEAM_ID must be set (10-char Apple team id)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

BUILD_DIR=build
ARCHIVE="$BUILD_DIR/$APP.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/$APP.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving"
xcodebuild \
    -project "$APP.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive

echo "==> Writing ExportOptions.plist"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Exporting .app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

echo "==> Packaging DMG"
hdiutil create \
    -volname "$APP" \
    -srcfolder "$EXPORT_DIR/$APP.app" \
    -ov -format UDZO \
    "$DMG"

echo "==> Notarizing (this can take several minutes)"
xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler staple "$EXPORT_DIR/$APP.app"

echo "==> Verifying"
spctl -a -t exec -vv "$EXPORT_DIR/$APP.app"
xcrun stapler validate "$DMG"

echo
echo "Done: $DMG"
