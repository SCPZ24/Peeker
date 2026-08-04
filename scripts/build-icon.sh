#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_IMAGE="$ROOT_DIR/LOGO.png"
OUTPUT_ICON="${1:-$ROOT_DIR/dist/Peeker.icns}"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "icon source not found: $SOURCE_IMAGE" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/peeker-icon.XXXXXX")"
ICONSET_DIR="$TEMP_DIR/Peeker.iconset"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$ICONSET_DIR" "$(dirname "$OUTPUT_ICON")"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT_DIR/.build/ModuleCache}"
"$ROOT_DIR/scripts/generate-iconset.swift" "$SOURCE_IMAGE" "$ICONSET_DIR"

/usr/bin/sips -s format tiff "$ICONSET_DIR/icon_16x16.png" --out "$TEMP_DIR/icon-16.tiff" >/dev/null
/usr/bin/sips -s format tiff "$ICONSET_DIR/icon_32x32.png" --out "$TEMP_DIR/icon-32.tiff" >/dev/null
/usr/bin/sips -s format tiff "$ICONSET_DIR/icon_128x128.png" --out "$TEMP_DIR/icon-128.tiff" >/dev/null
/usr/bin/sips -s format tiff "$ICONSET_DIR/icon_256x256.png" --out "$TEMP_DIR/icon-256.tiff" >/dev/null
/usr/bin/sips -s format tiff "$ICONSET_DIR/icon_512x512.png" --out "$TEMP_DIR/icon-512.tiff" >/dev/null
/usr/bin/sips -s format tiff "$ICONSET_DIR/icon_512x512@2x.png" --out "$TEMP_DIR/icon-1024.tiff" >/dev/null

/usr/bin/tiffutil -cat \
  "$TEMP_DIR/icon-16.tiff" \
  "$TEMP_DIR/icon-32.tiff" \
  "$TEMP_DIR/icon-128.tiff" \
  "$TEMP_DIR/icon-256.tiff" \
  "$TEMP_DIR/icon-512.tiff" \
  "$TEMP_DIR/icon-1024.tiff" \
  -out "$TEMP_DIR/Peeker.tiff" >/dev/null 2>&1
/usr/bin/tiff2icns "$TEMP_DIR/Peeker.tiff" "$OUTPUT_ICON"
echo "$OUTPUT_ICON"
