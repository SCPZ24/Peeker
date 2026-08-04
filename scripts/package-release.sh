#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.2}"
ARCHIVE="$ROOT_DIR/dist/Peeker-v$VERSION.zip"
SOURCE_PLIST="$ROOT_DIR/Resources/Info.plist"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "release version must use three numeric components: $VERSION" >&2
  exit 2
fi

SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")"
if [[ "$VERSION" != "$SOURCE_VERSION" ]]; then
  echo "release version $VERSION does not match CFBundleShortVersionString $SOURCE_VERSION" >&2
  exit 3
fi

"$ROOT_DIR/scripts/build-app.sh" release

BUILT_PLIST="$ROOT_DIR/dist/Peeker.app/Contents/Info.plist"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_PLIST")"
if [[ "$VERSION" != "$BUILT_VERSION" ]]; then
  echo "built app version $BUILT_VERSION does not match release version $VERSION" >&2
  exit 4
fi

rm -f "$ARCHIVE" "$ARCHIVE.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ROOT_DIR/dist/Peeker.app" "$ARCHIVE"
ARCHIVE_DIRECTORY="$(dirname "$ARCHIVE")"
ARCHIVE_FILENAME="$(basename "$ARCHIVE")"
(
  cd "$ARCHIVE_DIRECTORY"
  /usr/bin/shasum -a 256 "$ARCHIVE_FILENAME" > "$ARCHIVE_FILENAME.sha256"
)

echo "Local archive: $ARCHIVE"
echo "SHA-256: $(/usr/bin/awk '{print $1}' "$ARCHIVE.sha256")"
