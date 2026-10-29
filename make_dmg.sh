#!/bin/bash
# Build a drag-to-install DMG for Disk Health.
# Usage: ./make_dmg.sh [version]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP="build/DiskHealth.app"
DMG="build/DiskHealth-${VERSION}-macOS-arm64.dmg"
VOL="Disk Health"
RW="build/rw.dmg"
STAGE="build/dmg-stage"

[ -d "$APP" ] || ./build.sh

rm -rf "$STAGE"
mkdir -p "$STAGE/$VOL/.background"
cp -R "$APP" "$STAGE/$VOL/"
ln -s /Applications "$STAGE/$VOL/Applications"
cp src/dmg-background.png "$STAGE/$VOL/.background/"

rm -f "$RW" "$DMG"
hdiutil create -quiet -srcfolder "$STAGE/$VOL" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW"

DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -m1 '^/dev/' | awk '{print $1}')"
MNT="/Volumes/$VOL"

# Nice icon layout. Needs Finder automation permission; skip quietly if unavailable.
osascript <<OSA || echo "! Finder layout skipped (no automation permission) — DMG still works."
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background picture of viewOptions to file ".background:dmg-background.png"
    set position of item "DiskHealth.app" of container window to {165, 200}
    set position of item "Applications" of container window to {495, 200}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
OSA

sync
hdiutil detach "$DEV" -quiet || hdiutil detach "$DEV" -force -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -f "$RW"
rm -rf "$STAGE"

echo "Built: $PWD/$DMG"
shasum -a 256 "$DMG"
