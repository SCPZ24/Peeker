#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.4}"
CASK="$($ROOT_DIR/scripts/render-cask.sh "$VERSION")"
export HOMEBREW_CACHE="$ROOT_DIR/.build/homebrew-cache"
export HOMEBREW_TEMP="$ROOT_DIR/.build/homebrew-temp"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_DEVELOPER=1
mkdir -p "$HOMEBREW_CACHE" "$HOMEBREW_TEMP"

/usr/bin/ruby -c "$CASK"
if command -v brew >/dev/null 2>&1; then
  brew style --cask "$CASK"
else
  echo "Homebrew not installed; skipped brew style --cask."
fi
