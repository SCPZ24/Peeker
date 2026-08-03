#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/Peeker.app}"

test -x "$APP_BUNDLE/Contents/MacOS/Peeker"
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || {
  echo "Gatekeeper rejected this local artifact. This is expected for ad-hoc, unnotarized builds." >&2
}
