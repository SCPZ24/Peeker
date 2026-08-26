#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/Peeker.app}"
EXPECTED_VERSION="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Peeker"
CLI_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/peeker-cli"
AGENTOR_HELPER="$APP_BUNDLE/Contents/MacOS/peeker-agentor-hook"
AGENTOR_RESOURCES="$APP_BUNDLE/Contents/Resources/Agentor"

test -x "$EXECUTABLE"
test -x "$CLI_EXECUTABLE"
test -x "$AGENTOR_HELPER"
test "$(basename "$EXECUTABLE")" != "$(basename "$CLI_EXECUTABLE")"
test "$(basename "$AGENTOR_HELPER")" != "$(basename "$CLI_EXECUTABLE")"
/usr/bin/plutil -lint "$INFO_PLIST"

ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
test "$ACTUAL_VERSION" = "$EXPECTED_VERSION"

ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")"
test "$ICON_FILE" = "Peeker.icns"
test -s "$APP_BUNDLE/Contents/Resources/$ICON_FILE"

BINARY_DESCRIPTION="$(/usr/bin/file "$EXECUTABLE")"
case "$BINARY_DESCRIPTION" in
  *arm64*) ;;
  *)
    echo "release binary is not arm64: $BINARY_DESCRIPTION" >&2
    exit 1
    ;;
esac
CLI_DESCRIPTION="$(/usr/bin/file "$CLI_EXECUTABLE")"
case "$CLI_DESCRIPTION" in
  *arm64*) ;;
  *) echo "CLI binary is not arm64: $CLI_DESCRIPTION" >&2; exit 1 ;;
esac
case "$CLI_DESCRIPTION" in
  *x86_64*) echo "CLI binary unexpectedly contains x86_64: $CLI_DESCRIPTION" >&2; exit 1 ;;
esac
HELPER_DESCRIPTION="$(/usr/bin/file "$AGENTOR_HELPER")"
case "$HELPER_DESCRIPTION" in
  *arm64*) ;;
  *) echo "Agentor helper is not arm64: $HELPER_DESCRIPTION" >&2; exit 1 ;;
esac
case "$HELPER_DESCRIPTION" in
  *x86_64*) echo "Agentor helper unexpectedly contains x86_64: $HELPER_DESCRIPTION" >&2; exit 1 ;;
esac
/usr/bin/ruby -rjson -rdigest -e '
  root = ARGV.fetch(0)
  manifest = JSON.parse(File.read(File.join(root, "manifest.json")))
  abort "invalid Agentor manifest" unless manifest["schemaVersion"] == 1 && manifest["resourceVersion"] == 1
  manifest.fetch("files").each do |path, expected|
    file = File.join(root, path)
    abort "missing Agentor resource: #{path}" unless File.file?(file)
    actual = Digest::SHA256.file(file).hexdigest
    abort "Agentor resource hash mismatch: #{path}" unless actual == expected
  end
' "$AGENTOR_RESOURCES"
CLI_VERSION_JSON="$("$CLI_EXECUTABLE" --version)"
CLI_ROOT_HELP="$("$CLI_EXECUTABLE" --help)"
CLI_FEATURE_HELP="$("$CLI_EXECUTABLE" scheduler --help)"
CLI_LEAF_HELP="$("$CLI_EXECUTABLE" scheduler source import --help)"
case "$CLI_ROOT_HELP" in
  *"Usage: peeker <command>"*) ;;
  *) echo "embedded CLI root help is invalid" >&2; exit 1 ;;
esac
case "$CLI_ROOT_HELP" in
  *agentor*) echo "Agentor unexpectedly appeared in public CLI help" >&2; exit 1 ;;
  *) ;;
esac
case "$CLI_FEATURE_HELP" in
  *"Usage: peeker scheduler <command> [arguments]"*) ;;
  *) echo "embedded CLI feature help is invalid" >&2; exit 1 ;;
esac
case "$CLI_LEAF_HELP" in
  *"Usage: peeker scheduler source import --file <path>"*) ;;
  *) echo "embedded CLI leaf help is invalid" >&2; exit 1 ;;
esac
/usr/bin/ruby -rjson -e '
  value = JSON.parse(ARGV.fetch(0))
  abort "invalid CLI schema" unless value["schemaVersion"] == 1 && value["ok"] == true
  data = value.fetch("data")
  abort "invalid CLI version" unless data["cliVersion"] == ARGV.fetch(1) && data["protocolVersion"] == 1
' "$CLI_VERSION_JSON" "$EXPECTED_VERSION"

case "$BINARY_DESCRIPTION" in
  *x86_64*)
    echo "release binary unexpectedly contains x86_64: $BINARY_DESCRIPTION" >&2
    exit 1
    ;;
esac

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1)"
case "$SIGNING_DETAILS" in
  *Signature=adhoc*) ;;
  *)
    echo "release bundle is not ad-hoc signed" >&2
    echo "$SIGNING_DETAILS" >&2
    exit 1
    ;;
esac
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE" || {
  echo "Gatekeeper rejected this local artifact. This is expected for ad-hoc, unnotarized builds." >&2
}
