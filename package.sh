#!/bin/bash
# Builds a universal (Apple silicon + Intel) EchoHunt.app and zips it for sharing.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/EchoHunt.app"
MACOS="$APP/Contents/MacOS"
DEPLOY_TARGET="12.0"

rm -rf dist
mkdir -p "$MACOS" "$APP/Contents/Resources"

echo "Compiling arm64…"
swiftc -O -target "arm64-apple-macos$DEPLOY_TARGET" $(find Sources -name "*.swift") -o dist/EchoHunt-arm64

echo "Compiling x86_64…"
swiftc -O -target "x86_64-apple-macos$DEPLOY_TARGET" $(find Sources -name "*.swift") -o dist/EchoHunt-x86_64

echo "Merging into a universal binary…"
lipo -create dist/EchoHunt-arm64 dist/EchoHunt-x86_64 -output "$MACOS/EchoHunt"
rm dist/EchoHunt-arm64 dist/EchoHunt-x86_64
lipo -info "$MACOS/EchoHunt"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Echo Hunt</string>
  <key>CFBundleDisplayName</key><string>Echo Hunt</string>
  <key>CFBundleExecutable</key><string>EchoHunt</string>
  <key>CFBundleIdentifier</key><string>local.playground.echo-hunt</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>$DEPLOY_TARGET</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Echo Hunt finds your opponent's Mac on the local network to play a two-player match.</string>
  <key>NSBonjourServices</key>
  <array><string>_echohunt._tcp</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
</dict>
</plist>
PLIST

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. This is NOT a Developer ID signature, so Gatekeeper will
# still warn on another machine — see READ-ME-FIRST.txt.
codesign --force --deep --sign - "$APP"

# Strip extended attributes before archiving. Otherwise the zip carries "._"
# AppleDouble companions, and any unzip tool other than macOS's own extracts
# them as real files inside the bundle, invalidating the signature — the app
# then arrives "damaged". The signature itself lives in the Mach-O and
# _CodeSignature/, so it survives this.
xattr -cr "$APP"
codesign --verify --verbose "$APP" 2>&1 | tail -2

# A .app is a directory bundle, so it has to be archived to survive transfer —
# ditto preserves the bundle structure and the executable bit. Just the app,
# nothing alongside it.
echo "Zipping…"
# No --sequesterRsrc: it spills a __MACOSX folder out beside the app when the
# recipient unzips.
ditto -c -k --keepParent "$APP" dist/EchoHunt.zip

echo
echo "Ready to send:  $(cd dist && pwd)/EchoHunt.zip  ($(du -h dist/EchoHunt.zip | cut -f1))"
