#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-2.0.1}"
ARCHIVE="${2:-$ROOT_DIR/dist/Peeker-v$VERSION.zip}"
OUTPUT="${3:-$ROOT_DIR/.build/verification/peeker.rb}"
CASK="$($ROOT_DIR/scripts/render-cask.sh "$VERSION" "$ARCHIVE" "$OUTPUT")"
export HOMEBREW_CACHE="$ROOT_DIR/.build/homebrew-cache"
export HOMEBREW_TEMP="$ROOT_DIR/.build/homebrew-temp"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_DEVELOPER=1
mkdir -p "$HOMEBREW_CACHE" "$HOMEBREW_TEMP"

/usr/bin/ruby -c "$CASK"
grep -q -- 'peeker-cli.*target: "peeker"' "$CASK"
if command -v brew >/dev/null 2>&1; then
  brew style "$CASK"
else
  echo "Homebrew not installed; skipped brew style --cask."
fi
