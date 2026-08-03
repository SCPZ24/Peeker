#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.0}"
ARCHIVE="$ROOT_DIR/dist/Peeker-v$VERSION.zip"

"$ROOT_DIR/scripts/build-app.sh" release
rm -f "$ARCHIVE" "$ARCHIVE.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/Peeker.app" "$ARCHIVE"
/usr/bin/shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

echo "Local archive: $ARCHIVE"
echo "SHA-256: $(/usr/bin/awk '{print $1}' "$ARCHIVE.sha256")"
