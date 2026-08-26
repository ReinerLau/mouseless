#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_NAME="Mouseless TCC Spike"
EXECUTABLE_NAME="MouselessTCCSpike"
BUILD_ROOT="$SCRIPT_DIR/.build"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
EXPECTED_BUNDLE="$SCRIPT_DIR/.build/Mouseless TCC Spike.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Mouseless Local Development}"
TARGET_ARCH=$(uname -m)
BUILD_NUMBER=$(date -u +%Y%m%d%H%M%S)

if pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then
  printf 'Quit “%s” from its menu bar item, then run this script again.\n' "$APP_NAME" >&2
  exit 1
fi

if [[ "$APP_BUNDLE" != "$EXPECTED_BUNDLE" || "$APP_BUNDLE" == "/" ]]; then
  printf 'Refusing to clean unexpected bundle path: %s\n' "$APP_BUNDLE" >&2
  exit 1
fi

rm -rf -- "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

xcrun --sdk macosx swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target "$TARGET_ARCH-apple-macos14.0" \
  "$SCRIPT_DIR/Sources/main.swift" \
  -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework Carbon \
  -framework CoreGraphics \
  -framework OSLog

PLIST="$APP_BUNDLE/Contents/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleDisplayName -string "$APP_NAME" "$PLIST"
plutil -insert CFBundleExecutable -string "$EXECUTABLE_NAME" "$PLIST"
plutil -insert CFBundleIdentifier -string "com.reinerlau.mouseless.tcc-spike" "$PLIST"
plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$PLIST"
plutil -insert CFBundleName -string "$APP_NAME" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "0.0.1" "$PLIST"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
plutil -insert LSMinimumSystemVersion -string "14.0" "$PLIST"
plutil -insert LSUIElement -bool true "$PLIST"
plutil -insert NSHighResolutionCapable -bool true "$PLIST"

codesign --force \
  --options runtime \
  --timestamp=none \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign --display --requirements - "$APP_BUNDLE"

printf '\nBuilt and signed: %s\n' "$APP_BUNDLE"
printf 'Bundle build number: %s\n' "$BUILD_NUMBER"
printf 'Launching the spike…\n'
open "$APP_BUNDLE"
