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
grep -q -- 'peeker-cli.*target: "peeker"' "$ROOT_DIR/Casks/peeker.rb.template"
grep -q -- 'CLI_VERSION_JSON' "$ROOT_DIR/scripts/verify-bundle.sh"
grep -q -- 'AGENTOR_HELPER' "$ROOT_DIR/scripts/verify-bundle.sh"
grep -q -- 'Agentor resource hash mismatch' "$ROOT_DIR/scripts/verify-bundle.sh"
grep -q -- 'Resources/Targetor' "$ROOT_DIR/scripts/build-app.sh"
grep -q -- 'Lucide resource hash mismatch' "$ROOT_DIR/scripts/verify-bundle.sh"
grep -q -- 'iconCount.*209' "$ROOT_DIR/scripts/verify-bundle.sh"
python3 "$ROOT_DIR/scripts/vendor-lucide.py" --check
if grep -Eq -- 'vendor-lucide|curl|wget|git clone' "$ROOT_DIR/scripts/build-app.sh" "$ROOT_DIR/scripts/package-release.sh"; then
  echo "Build and release scripts must not fetch or regenerate Lucide resources." >&2
  exit 1
fi
grep -q -- 'LICENSE-ISC.txt' "$ROOT_DIR/scripts/verify-bundle.sh"
grep -q -- 'LICENSE-MIT.txt' "$ROOT_DIR/scripts/verify-bundle.sh"
grep -q -- '2.1.1' "$ROOT_DIR/Resources/Info.plist"
grep -q -- '<string>4</string>' "$ROOT_DIR/Resources/Info.plist"

echo "release script contract passed"
