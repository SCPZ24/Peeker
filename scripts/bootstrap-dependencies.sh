#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "This is the explicit networked dependency bootstrap step."
echo "It resolves GRDB.swift once and prepares the project-local checkout."

swift package resolve --disable-sandbox
swift build --disable-sandbox -c debug --product Peeker

echo "Dependencies bootstrapped. Future builds use scripts/build-app.sh offline."
