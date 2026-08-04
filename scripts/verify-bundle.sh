#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/Peeker.app}"
EXPECTED_VERSION="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Peeker"

test -x "$EXECUTABLE"
/usr/bin/plutil -lint "$INFO_PLIST"

ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
test "$ACTUAL_VERSION" = "$EXPECTED_VERSION"

ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")"
test "$ICON_FILE" = "Peeker.icns"
test -s "$APP_BUNDLE/Contents/Resources/$ICON_FILE"

BINARY_DESCRIPTION="$(/usr/bin/file "$EXECUTABLE")"
case "$BINARY_DESCRIPTION" in
  *arm64*) ;;
  *)
    echo "release binary is not arm64: $BINARY_DESCRIPTION" >&2
    exit 1
    ;;
esac
case "$BINARY_DESCRIPTION" in
  *x86_64*)
    echo "release binary unexpectedly contains x86_64: $BINARY_DESCRIPTION" >&2
    exit 1
    ;;
esac

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1)"
case "$SIGNING_DETAILS" in
  *Signature=adhoc*) ;;
  *)
    echo "release bundle is not ad-hoc signed" >&2
    echo "$SIGNING_DETAILS" >&2
    exit 1
    ;;
esac
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || {
  echo "Gatekeeper rejected this local artifact. This is expected for ad-hoc, unnotarized builds." >&2
}
