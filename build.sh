#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="MacBridge.app"
BINARY_NAME="MacBridge"

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
if [[ -f "Sources/MacBridge/Resources/MacBridgeIcon.icns" ]]; then
    cp "Sources/MacBridge/Resources/MacBridgeIcon.icns" "$APP_NAME/Contents/Resources/MacBridgeIcon.icns"
fi

SIGN_IDENTITY="${MACBRIDGE_SIGN_IDENTITY:-MacBridge Dev}"
echo "→ Signing with identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_NAME"

echo "→ Killing any running MacBridge instance so next launch uses the fresh binary..."
pkill -x MacBridge 2>/dev/null || true

INSTALL_PATH="/Applications/$APP_NAME"
echo "→ Installing to $INSTALL_PATH..."
if rm -rf "$INSTALL_PATH" 2>/dev/null && cp -R "$APP_NAME" "$INSTALL_PATH" 2>/dev/null; then
    echo "   ✓ copied"
    INSTALLED=1
else
    echo "   ✗ install failed (permission denied?). Try: sudo cp -R $APP_NAME /Applications/"
    INSTALLED=0
fi

echo ""
echo "✅ Built $(pwd)/$APP_NAME"
if [[ "$INSTALLED" == "1" ]]; then
    echo ""
    echo "Run: open -a MacBridge"
else
    echo ""
    echo "Run: open $APP_NAME"
fi
