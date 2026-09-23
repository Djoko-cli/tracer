#!/bin/bash
# Builds Tracer.app (release) and installs it in ~/Applications (or the folder given as $1).
set -euo pipefail
cd "$(dirname "$0")/.."

# The build folder must live outside iCloud-synced folders (Desktop, Documents):
# codesign refuses the extended attributes iCloud adds to files.
SCRATCH="${TRACER_BUILD_DIR:-$HOME/Library/Caches/TracerBuild}"
DEST="${1:-$HOME/Applications}"
VERSION="$(cat VERSION 2>/dev/null || echo 0.1.0)"

swift build -c release --scratch-path "$SCRATCH" --product Tracer

APP="$DEST/Tracer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SCRATCH/release/Tracer" "$APP/Contents/MacOS/Tracer"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tracer</string>
    <key>CFBundleDisplayName</key><string>Tracer</string>
    <key>CFBundleIdentifier</key><string>film.majid.tracer</string>
    <key>CFBundleExecutable</key><string>Tracer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Image</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.image</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✔ $APP"
