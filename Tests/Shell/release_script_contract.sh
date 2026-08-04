#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

test -x "$ROOT_DIR/scripts/build-icon.sh"
grep -q -- 'CFBundleIconFile' "$ROOT_DIR/Resources/Info.plist"
grep -q -- 'Peeker.icns' "$ROOT_DIR/Resources/Info.plist"
grep -q -- 'build-icon.sh' "$ROOT_DIR/scripts/build-app.sh"
grep -q -- 'CFBundleShortVersionString' "$ROOT_DIR/scripts/package-release.sh"
grep -q -- 'basename "$ARCHIVE"' "$ROOT_DIR/scripts/package-release.sh"
grep -q -- 'depends_on arch: :arm64' "$ROOT_DIR/Casks/peeker.rb.template"

echo "release script contract passed"
