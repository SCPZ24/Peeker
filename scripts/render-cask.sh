#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-1.0.4}"
ARCHIVE="${2:-$ROOT_DIR/dist/Peeker-v$VERSION.zip}"
OUTPUT="${3:-$ROOT_DIR/dist/Casks/peeker.rb}"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "archive not found: $ARCHIVE" >&2
  exit 1
fi

SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
mkdir -p "$(dirname "$OUTPUT")"
/usr/bin/sed \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__SHA256__/$SHA256/g" \
  "$ROOT_DIR/Casks/peeker.rb.template" > "$OUTPUT"
echo "$OUTPUT"
