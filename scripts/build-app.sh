#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Peeker"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"

cd "$ROOT_DIR"
swift build --disable-sandbox -c "$CONFIGURATION" --product "$APP_NAME"
BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS_DIR/$APP_NAME"

SIGN_IDENTITY="${PEEKER_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE"
  echo "Built an ad-hoc signed local bundle: $APP_BUNDLE"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT_DIR/Resources/Peeker.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"
  echo "Built a Developer ID signed bundle: $APP_BUNDLE"
fi
