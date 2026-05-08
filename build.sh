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

SIGN_IDENTITY="${MACBRIDGE_SIGN_IDENTITY:-MacBridge Dev}"
echo "→ Signing with identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_NAME"

echo "→ Killing any running MacBridge instance so next launch uses the fresh binary..."
pkill -x MacBridge 2>/dev/null || true

echo ""
echo "✅ Built $(pwd)/$APP_NAME"
echo ""
echo "Run: open $APP_NAME"
