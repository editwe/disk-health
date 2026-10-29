#!/bin/bash
# Build "Disk Health" — a tiny macOS app that reads NVMe SMART health.
set -euo pipefail
cd "$(dirname "$0")"

SRC="src"
OUT="build"
APP="$OUT/DiskHealth.app"
TARGET="arm64-apple-macos13.0"
SDK="$(xcrun --show-sdk-path)"

mkdir -p "$OUT"

# 1. C reader (IOKit -> NVMe SMART log page 0x02 -> JSON)
clang -O2 -Wall -target "$TARGET" -isysroot "$SDK" \
  -c "$SRC/HealthReader.c" -o "$OUT/HealthReader.o" -I"$SRC"

# 2. Swift shell (AppKit + WebKit)
swiftc -O -swift-version 5 -module-cache-path "$OUT/modulecache" -target "$TARGET" \
  -import-objc-header "$SRC/HealthReader.h" \
  "$SRC/main.swift" "$SRC/AppDelegate.swift" "$OUT/HealthReader.o" \
  -o "$OUT/DiskHealth" \
  -framework AppKit -framework WebKit -framework IOKit

# 3. App icon (generated from the 1024px master, no extra tooling needed)
rm -rf "$OUT/AppIcon.iconset"
mkdir -p "$OUT/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC/icon_1024.png" --out "$OUT/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$SRC/icon_1024.png" --out "$OUT/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$OUT/AppIcon.iconset" -o "$OUT/AppIcon.icns"

# 4. Assemble the bundle
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/DiskHealth" "$APP/Contents/MacOS/DiskHealth"
cp "$SRC/index.html" "$APP/Contents/Resources/index.html"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
cp "$OUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$SRC/en.lproj" "$SRC/zh-Hans.lproj" "$APP/Contents/Resources/"

# 5. Ad-hoc signature (local use only, not notarized)
codesign --force --sign - --identifier com.ch.diskhealth "$APP" >/dev/null 2>&1

echo "Built: $PWD/$APP"
