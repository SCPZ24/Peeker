#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-app.sh"
RUN_SCRIPT="$ROOT_DIR/script/build_and_run.sh"

grep -q -- '--disable-automatic-resolution' "$BUILD_SCRIPT"
! grep -q -- '--skip-update' "$BUILD_SCRIPT"
grep -q -- 'run-existing' "$RUN_SCRIPT"
grep -q -- 'Package.resolved' "$BUILD_SCRIPT"
grep -q -- '--product peeker-cli' "$BUILD_SCRIPT"
grep -q -- '"$MACOS_DIR/peeker-cli"' "$BUILD_SCRIPT"
test -x "$ROOT_DIR/scripts/bootstrap-dependencies.sh"

echo "build script contract passed"
