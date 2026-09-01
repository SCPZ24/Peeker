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
AGENTOR_LOGOS="$AGENTOR_RESOURCES/logos"
LUCIDE_RESOURCES="$APP_BUNDLE/Contents/Resources/Targetor/Lucide"
LUCIDE_MANIFEST="$LUCIDE_RESOURCES/manifest.json"

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
EXPECTED_AGENTOR_LOGOS=(claude codex hermes opencode pi)
test "$(find "$AGENTOR_LOGOS" -maxdepth 1 -type f -name '*.svg' | wc -l | tr -d ' ')" = "${#EXPECTED_AGENTOR_LOGOS[@]}"
for logo in "${EXPECTED_AGENTOR_LOGOS[@]}"; do
  LOGO_FILE="$AGENTOR_LOGOS/$logo.svg"
  test -s "$LOGO_FILE"
  case "$(/usr/bin/file "$LOGO_FILE")" in
    *"SVG Scalable Vector Graphics image"*) ;;
    *) echo "invalid Agentor logo: $LOGO_FILE" >&2; exit 1 ;;
  esac
  /usr/bin/sips -g pixelWidth -g pixelHeight "$LOGO_FILE" >/dev/null
  LOGO_PREVIEW="$(mktemp -t "peeker-agentor-$logo").png"
  if ! RENDER_OUTPUT="$(CORESVG_VERBOSE=1 /usr/bin/sips -s format png --resampleHeightWidth 64 64 "$LOGO_FILE" --out "$LOGO_PREVIEW" 2>&1)"; then
    rm -f "$LOGO_PREVIEW"
    echo "failed to render Agentor logo: $LOGO_FILE" >&2
    exit 1
  fi
  rm -f "$LOGO_PREVIEW"
  case "$RENDER_OUTPUT" in
    *Warning*|*Error*) echo "CoreSVG rejected Agentor logo: $LOGO_FILE" >&2; exit 1 ;;
  esac
done

/usr/bin/ruby -rjson -rdigest -rpathname -e '
  root = ARGV.fetch(0)
  manifest = JSON.parse(File.read(File.join(root, "manifest.json")))
  abort "invalid Lucide manifest" unless manifest["schemaVersion"] == 1 &&
    manifest["featureID"] == "targetor" && manifest["version"] == "1.27.0" &&
    manifest["upstreamCommit"] == "4aec3f892fd6c23063bc2fead83c899b5d412b1c"
  icons = manifest.fetch("icons")
  abort "Lucide icon count mismatch" unless manifest["iconCount"] == 1756 && icons.length == 1756
  icons.each do |icon|
    path = icon.fetch("file")
    abort "invalid Lucide resource path: #{path}" if Pathname.new(path).absolute? || path.split("/").include?("..")
    file = File.join(root, path)
    abort "missing Lucide resource: #{path}" unless File.file?(file)
    abort "Lucide resource hash mismatch: #{path}" unless Digest::SHA256.file(file).hexdigest == icon.fetch("sha256")
  end
' "$LUCIDE_RESOURCES"
test -s "$LUCIDE_RESOURCES/LICENSE-ISC.txt"
test -s "$LUCIDE_RESOURCES/LICENSE-MIT.txt"
test "$(find "$LUCIDE_RESOURCES/icons" -maxdepth 1 -type f -name '*.svg' | wc -l | tr -d ' ')" = "$(/usr/bin/ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("iconCount")' "$LUCIDE_MANIFEST")"
for icon in target chevrons-up rocket badge-check circle; do
  SVG_FILE="$LUCIDE_RESOURCES/icons/$icon.svg"
  test -s "$SVG_FILE"
  PREVIEW="$(mktemp -t "peeker-lucide-$icon").png"
  if ! RENDER_OUTPUT="$(CORESVG_VERBOSE=1 /usr/bin/sips -s format png --resampleHeightWidth 64 64 "$SVG_FILE" --out "$PREVIEW" 2>&1)"; then
    rm -f "$PREVIEW"
    echo "failed to render Lucide icon: $SVG_FILE" >&2
    exit 1
  fi
  rm -f "$PREVIEW"
  case "$RENDER_OUTPUT" in
    *Warning*|*Error*) echo "CoreSVG rejected Lucide icon: $SVG_FILE" >&2; exit 1 ;;
  esac
done

CLI_VERSION_JSON="$("$CLI_EXECUTABLE" --version)"
CLI_ROOT_HELP="$("$CLI_EXECUTABLE" --help)"
CLI_FEATURE_HELP="$("$CLI_EXECUTABLE" scheduler --help)"
CLI_LEAF_HELP="$("$CLI_EXECUTABLE" scheduler source import --help)"
CLI_TIMER_TEMPORARY_HELP="$("$CLI_EXECUTABLE" timer temporary --help)"
CLI_TARGETOR_HELP="$("$CLI_EXECUTABLE" targetor --help)"
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
case "$CLI_TIMER_TEMPORARY_HELP" in
  *"Usage: peeker timer temporary <command> [arguments]"*) ;;
  *) echo "embedded Timer temporary help is invalid" >&2; exit 1 ;;
esac
case "$CLI_TARGETOR_HELP" in
  *"Usage: peeker targetor <command> [arguments]"*) ;;
  *) echo "embedded Targetor help is invalid" >&2; exit 1 ;;
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
