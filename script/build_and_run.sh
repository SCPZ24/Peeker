#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Peeker"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
BUNDLE_ID="com.scpz24.Peeker"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

build_app() {
  "$ROOT_DIR/scripts/build-app.sh" debug
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

require_existing_app() {
  if [[ ! -x "$APP_BINARY" ]]; then
    echo "No existing Peeker.app found at $APP_BUNDLE. Build it once with: $0 run" >&2
    exit 3
  fi
}

case "$MODE" in
  run)
    build_app
    open_app
    ;;
  run-existing|--run-existing)
    require_existing_app
    open_app
    ;;
  --debug|debug)
    build_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_app
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|run-existing|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
