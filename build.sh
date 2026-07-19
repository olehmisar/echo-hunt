#!/bin/bash
# Builds EchoHunt.app into build/
set -euo pipefail
cd "$(dirname "$0")"

APP="build/EchoHunt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O Sources/*.swift -o "$APP/Contents/MacOS/EchoHunt"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>EchoHunt</string>
  <key>CFBundleExecutable</key><string>EchoHunt</string>
  <key>CFBundleIdentifier</key><string>local.playground.echo-hunt</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
