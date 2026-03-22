#!/bin/bash

APP_NAME="MacCleaner"
SRC_DIR="Sources"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile
echo "Compiling swift files..."
swiftc -o "$MACOS_DIR/$APP_NAME" \
  -target arm64-apple-macosx12.0 \
  -sdk $(xcrun --show-sdk-path --sdk macosx) \
  -framework SwiftUI -framework AppKit \
  $(find $SRC_DIR -name "*.swift")

if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

# Copy Info.plist
cp Info.plist "$CONTENTS_DIR/"

# Sign the app with entitlements
echo "Signing the app..."
codesign --force --deep --sign - --entitlements MacCleaner.entitlements "$APP_DIR"

echo "Build successful! App is at $APP_DIR"
