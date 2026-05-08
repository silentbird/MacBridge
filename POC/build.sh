#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="MacBridgePOC.app"
BINARY_NAME="MacBridgePOC"

echo "→ Building Swift package ($CONFIG)..."
if [[ "$CONFIG" == "release" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BUILD_DIR=".build/apple/Products/Release"
else
    swift build
    BUILD_DIR=".build/debug"
fi

EXECUTABLE="$BUILD_DIR/$BINARY_NAME"
if [[ ! -f "$EXECUTABLE" ]]; then
    echo "✗ Build output not found at $EXECUTABLE"
    exit 1
fi

echo "→ Packaging $APP_NAME..."
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"
cp "$EXECUTABLE" "$APP_NAME/Contents/MacOS/$BINARY_NAME"
cp Info.plist "$APP_NAME/Contents/Info.plist"

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - "$APP_NAME"

echo ""
echo "✅ Built $(pwd)/$APP_NAME"
echo ""
echo "Next steps:"
echo "  1. open $APP_NAME"
echo "  2. Click the keyboard icon in the menu bar"
echo "  3. Toggle 'Enable A → B test' — macOS will prompt for Accessibility"
echo "  4. Grant permission, then toggle again"
echo "  5. Open TextEdit, press A, expect B"
