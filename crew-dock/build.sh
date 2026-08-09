#!/bin/bash
# Build Crew.app with swiftc alone — the demo Mac has Command Line Tools but no
# full Xcode, so `xcodebuild` and anything with a package graph is unavailable.
#   ./build.sh        compile + assemble Crew.app
#   ./build.sh run    build, then launch it
set -euo pipefail
cd "$(dirname "$0")"

APP="Crew.app"
ASSETS="Assets"
UPSTREAM="https://github.com/ryanstephen/lil-agents"

# Character art from lil-agents (MIT). Fetched, not committed — it's 18MB of
# video and it belongs to upstream.
if [ ! -f "$ASSETS/walk-bruce-01.mov" ]; then
  echo "fetching character assets from lil-agents..."
  TMP=$(mktemp -d)
  git clone -q --depth 1 "$UPSTREAM" "$TMP/la"
  mkdir -p "$ASSETS"
  cp "$TMP/la/LilAgents/walk-bruce-01.mov" "$TMP/la/LilAgents/walk-jazz-01.mov" "$ASSETS/"
  rm -rf "$TMP"
fi

echo "compiling..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 \
  -framework AppKit -framework AVFoundation -framework Network \
  -o "$APP/Contents/MacOS/Crew" \
  Sources/*.swift

cp "$ASSETS"/*.mov "$APP/Contents/Resources/"
# The roster travels with the app. Absent, the dock falls back to the built-in
# three, so a missing manifest degrades rather than breaking the run.
[ -f characters.json ] && cp characters.json "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Crew</string>
  <key>CFBundleIdentifier</key><string>xyz.crew.dock</string>
  <key>CFBundleName</key><string>Crew</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "built $APP"
[ "${1:-}" = run ] && { pkill -f "$APP/Contents/MacOS/Crew" 2>/dev/null || true; sleep 1; open "$APP"; echo "launched"; }
exit 0
